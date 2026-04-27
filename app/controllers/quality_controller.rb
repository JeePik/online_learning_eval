require "csv"

class QualityController < ApplicationController
  INDICATOR_NAMES = {
    "content" => "Змістовність",
    "time" => "Часові витрати",
    "cost" => "Ресурсні витрати",
    "grade" => "Успішність",
    "science" => "Науковість",
    "complexity" => "Складність",
    "practice" => "Практична спрямованість",
    "assimilation" => "Засвоєння",
    "activity" => "Активність",
    "interest" => "Зацікавленість"
  }

  def index
  end

  def calculate
    session.delete(:normalized)
    session.delete(:integral)
    session.delete(:chart_data)

    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    file = params[:csv_file]

    if file.nil?
      respond_to do |format|
        format.html { redirect_to root_path, alert: "Завантажте CSV-файл" }
        format.turbo_stream do
          flash.now[:alert] = "Завантажте CSV-файл"
          render turbo_stream: turbo_stream.update("results", partial: "quality/results_empty")
        end
      end
      return
    end

    unless csv_file?(file)
      respond_to do |format|
        format.html { redirect_to root_path, alert: "Потрібен файл у форматі CSV (.csv)" }
        format.turbo_stream do
          flash.now[:alert] = "Потрібен файл у форматі CSV (.csv)"
          render turbo_stream: turbo_stream.update("results", partial: "quality/results_empty")
        end
      end
      return
    end

    Rails.logger.warn("[CALC] file=#{file.original_filename} size=#{file.size} type=#{file.content_type}")

    data = []
    begin
      CSV.open(file.path, headers: true) do |csv|
        csv.each do |row|
          data << row.to_h.transform_values(&:to_f)
        end
      end
    rescue CSV::MalformedCSVError
      respond_to do |format|
        format.html { redirect_to root_path, alert: "CSV файл пошкоджений або має неправильний формат" }
        format.turbo_stream do
          flash.now[:alert] = "CSV файл пошкоджений або має неправильний формат"
          render turbo_stream: turbo_stream.update("results", partial: "quality/results_empty")
        end
      end
      return
    end

    calculator = DidacticQualityCalculator.new(data)

    @normalized = calculator.normalized_indicators
    @integral   = calculator.integral_index

    raw = calculator.chart_data
    @chart_data = raw.transform_keys { |k| INDICATOR_NAMES[k] || k }

    @chart_uid = SecureRandom.hex(6)

    cache_key = (session[:dq_cache_key] ||= SecureRandom.hex(16))

    Rails.cache.write("dq:#{cache_key}:chart_data", @chart_data, expires_in: 2.hours)
    Rails.cache.write("dq:#{cache_key}:normalized", @normalized, expires_in: 2.hours)
    Rails.cache.write("dq:#{cache_key}:integral",   @integral,   expires_in: 2.hours)

    respond_to do |format|
      format.html { render :index }
      format.turbo_stream
    end
  end

  def download
    session.delete(:normalized)
    session.delete(:integral)
    session.delete(:chart_data)

    type = params[:type]
    cache_key = session[:dq_cache_key]

    unless cache_key.present?
      redirect_to root_path, alert: "Немає даних для завантаження. Спочатку виконайте обчислення."
      return
    end

    normalized = Rails.cache.read("dq:#{cache_key}:normalized")
    integral   = Rails.cache.read("dq:#{cache_key}:integral")

    if normalized.blank? || integral.blank?
      redirect_to root_path, alert: "Дані застаріли або очищені. Перерахуйте показники ще раз."
      return
    end

    case type
    when "normalized"
      csv = CSV.generate do |csv|
        headers = normalized.first&.keys
        csv << headers
        normalized.each { |row| csv << row.values }
      end
      send_data csv, filename: "normalized.csv"
      return

    when "integral"
      csv = CSV.generate do |csv|
        csv << ["integral_index"]
        csv << [integral]
      end
      send_data csv, filename: "integral.csv"
      return

    when "results"
      respond_to do |format|
        format.csv do
          csv = CSV.generate do |csv|
            csv << ["integral_index"]
            csv << [integral]
            csv << []
            csv << ["normalized_indicators"]
            headers = normalized.first&.keys
            csv << headers
            normalized.each { |row| csv << row.values }
          end
          send_data csv, filename: "results.csv"
        end

        format.pdf do
          chart_data = Rails.cache.read("dq:#{cache_key}:chart_data") || {}
          pdf_data = build_results_pdf(normalized: normalized, integral: integral, chart_data: chart_data)
          send_data pdf_data,
                    filename: "results.pdf",
                    type: "application/pdf",
                    disposition: "inline"
        end
      end
      return
    when "results_txt"
     txt = +"Звіт: Оцінювання якості e-навчання\n"
     txt << "Дата: #{Time.zone.now.strftime("%d.%m.%Y %H:%M")}\n\n"
     txt << "Інтегральний показник якості\n"
     txt << "D = #{integral}\n\n"
     txt << "Нормалізовані показники\n"

     headers = normalized.first&.keys || []
     txt << headers.join("\t") << "\n"
     normalized.each do |row|
     txt << headers.map { |k| row[k] }.join("\t") << "\n"
     end

     send_data txt,
            filename: "results.txt",
            type: "text/plain; charset=utf-8"
     return

    when "results_dat"
      dat = +"# E-learning quality results\n"
      dat << "# Generated: #{Time.zone.now.strftime("%d.%m.%Y %H:%M")}\n"
      dat << "# integral_index=#{integral}\n"
      dat << "\n"

      headers = normalized.first&.keys || []
      dat << headers.join("\t") << "\n"
      normalized.each do |row|
      dat << headers.map { |k| row[k] }.join("\t") << "\n"
      end

      send_data dat,
            filename: "results.dat",
            type: "application/octet-stream"
      return

    else
      redirect_to root_path, alert: "Невідомий тип завантаження"
      return
    end
  end

def calculate_subject_pairs
  if params[:file].blank?
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "subject_pairs_results",
          partial: "quality/subject_pairs_results_empty",
          locals: { error: "Оберіть CSV-файл." }
        )
      end
      format.html { redirect_to root_path(anchor: "subject-pairs-section"), alert: "Оберіть CSV-файл." }
    end
    return
  end

  file = params[:file]

  unless csv_file?(file)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "subject_pairs_results",
          partial: "quality/subject_pairs_results_empty",
          locals: { error: "Файл має бути у форматі CSV." }
        )
      end
      format.html { redirect_to root_path(anchor: "subject-pairs-section"), alert: "Файл має бути у форматі CSV." }
    end
    return
  end

  faculty    = params[:faculty].to_s.strip
  specialty  = params[:specialty].to_s.strip
  semester   = params[:semester].to_s.strip
  group_name = params[:group_name].to_s.strip
  discipline = params[:discipline].to_s.strip
  code       = params[:code].to_s.strip

  begin
    raw_rows = []
    CSV.open(file.path, headers: true) do |csv|
      csv.each do |row|
        raw_rows << row.to_h.transform_values(&:to_f)
      end
    end
  rescue CSV::MalformedCSVError
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "subject_pairs_results",
          partial: "quality/subject_pairs_results_empty",
          locals: { error: "CSV-файл пошкоджений або має некоректну структуру." }
        )
      end
      format.html { redirect_to root_path(anchor: "subject-pairs-section"), alert: "CSV-файл пошкоджений або має некоректну структуру." }
    end
    return
  end

  if raw_rows.blank?
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "subject_pairs_results",
          partial: "quality/subject_pairs_results_empty",
          locals: { error: "CSV-файл порожній." }
        )
      end
      format.html { redirect_to root_path(anchor: "subject-pairs-section"), alert: "CSV-файл порожній." }
    end
    return
  end

  if raw_rows.size != 5
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "subject_pairs_results",
          partial: "quality/subject_pairs_results_empty",
          locals: { error: "CSV повинен містити рівно 5 рядків — по одному для кожної пари." }
        )
      end
      format.html { redirect_to root_path(anchor: "subject-pairs-section"), alert: "CSV повинен містити рівно 5 рядків." }
    end
    return
  end

  required_headers = %w[content time cost grade science complexity practice assimilation activity interest]
  csv_headers = raw_rows.first.keys.map(&:to_s)
  missing_headers = required_headers - csv_headers

  if missing_headers.any?
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "subject_pairs_results",
          partial: "quality/subject_pairs_results_empty",
          locals: { error: "У CSV відсутні потрібні колонки: #{missing_headers.join(', ')}" }
        )
      end
      format.html { redirect_to root_path(anchor: "subject-pairs-section"), alert: "У CSV відсутні потрібні колонки." }
    end
    return
  end

  normalized_rows = raw_rows.map.with_index(1) do |row, index|
    calculator = DidacticQualityCalculator.new([row])

    normalized = calculator.normalized_indicators.first.transform_keys(&:to_s)
    integral   = calculator.integral_index.to_f.round(4)

    normalized.merge(
      "pair_number" => index,
      "integral" => integral
    )
  end

  overall_integral = (
    normalized_rows.sum { |r| r["integral"].to_f } / normalized_rows.size
  ).round(4)

  metadata = {
    "faculty"    => faculty,
    "specialty"  => specialty,
    "semester"   => semester,
    "group_name" => group_name,
    "discipline" => discipline,
    "code"       => code
  }

  session[:subject_pairs_metadata]   = metadata
  session[:subject_pairs_normalized] = normalized_rows
  session[:subject_pairs_integral]   = overall_integral

  response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
  response.headers["Pragma"] = "no-cache"
  response.headers["Expires"] = "0"

  respond_to do |format|
    format.turbo_stream do
      render turbo_stream: turbo_stream.update(
        "subject_pairs_results",
        partial: "quality/subject_pairs_results",
        locals: {
          metadata: metadata,
          normalized_rows: normalized_rows,
          overall_integral: overall_integral
        }
      )
    end

    format.html do
      redirect_to root_path(anchor: "subject-pairs-section")
    end
  end
end

  def export_subject_pairs
  metadata         = session[:subject_pairs_metadata]
  normalized_rows  = session[:subject_pairs_normalized]
  overall_integral = session[:subject_pairs_integral]

  if normalized_rows.blank?
    redirect_to root_path(anchor: "subject-pairs-section"), alert: "Немає даних для експорту."
    return
  end

  case params[:type]
  when "normalized"
    csv_data = CSV.generate(headers: true) do |csv|
      headers = normalized_rows.first.keys
      csv << headers
      normalized_rows.each do |row|
        csv << headers.map { |header| row[header] }
      end
    end

    send_data csv_data,
              filename: "subject_pairs_normalized.csv",
              type: "text/csv; charset=utf-8"

  when "integral"
    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["faculty", "specialty", "semester", "group_name", "discipline", "code", "overall_integral"]
      csv << [
        metadata["faculty"],
        metadata["specialty"],
        metadata["semester"],
        metadata["group_name"],
        metadata["discipline"],
        metadata["code"],
        overall_integral
      ]
    end

    send_data csv_data,
              filename: "subject_pairs_integral.csv",
              type: "text/csv; charset=utf-8"

  when "results"
    respond_to do |format|
      format.csv do
        csv_data = CSV.generate(headers: true) do |csv|
          csv << ["faculty", metadata["faculty"]]
          csv << ["specialty", metadata["specialty"]]
          csv << ["semester", metadata["semester"]]
          csv << ["group_name", metadata["group_name"]]
          csv << ["discipline", metadata["discipline"]]
          csv << ["code", metadata["code"]]
          csv << []
          csv << ["overall_integral", overall_integral]
          csv << []

          headers = normalized_rows.first.keys
          csv << headers
          normalized_rows.each do |row|
            csv << headers.map { |header| row[header] }
          end
        end

        send_data csv_data,
                  filename: "subject_pairs_results.csv",
                  type: "text/csv; charset=utf-8"
      end

      format.pdf do
        pdf_data = build_subject_pairs_results_pdf(
          metadata: metadata,
          normalized_rows: normalized_rows,
          overall_integral: overall_integral
        )

        send_data pdf_data,
                  filename: "subject_pairs_results.pdf",
                  type: "application/pdf",
                  disposition: "inline"
      end
    end

  when "results_txt"
    txt = +"Звіт: Розрахунок інтегрального показника якості для 5 пар дисципліни\n"
    txt << "Дата: #{Time.zone.now.strftime("%d.%m.%Y %H:%M")}\n\n"

    txt << "Дані дисципліни\n"
    txt << "Факультет: #{metadata["faculty"]}\n"
    txt << "Спеціальність: #{metadata["specialty"]}\n"
    txt << "Семестр: #{metadata["semester"]}\n"
    txt << "Група: #{metadata["group_name"]}\n"
    txt << "Назва дисципліни: #{metadata["discipline"]}\n"
    txt << "Шифр: #{metadata["code"]}\n\n"

    txt << "Інтегральний показник якості\n"
    txt << "D = #{overall_integral}\n\n"

    ordered_keys = %w[
      pair_number
      content
      time
      cost
      grade
      science
      complexity
      practice
      assimilation
      activity
      interest
      integral
    ]

    txt << "Нормалізовані показники для 5 пар\n"
    txt << ordered_keys.join("\t") << "\n"
    normalized_rows.each do |row|
      txt << ordered_keys.map { |k| row[k] }.join("\t") << "\n"
    end

    send_data txt,
              filename: "subject_pairs_results.txt",
              type: "text/plain; charset=utf-8"

  when "results_dat"
    dat = +"# Subject pairs quality results\n"
    dat << "# Generated: #{Time.zone.now.strftime("%d.%m.%Y %H:%M")}\n"
    dat << "# faculty=#{metadata["faculty"]}\n"
    dat << "# specialty=#{metadata["specialty"]}\n"
    dat << "# semester=#{metadata["semester"]}\n"
    dat << "# group_name=#{metadata["group_name"]}\n"
    dat << "# discipline=#{metadata["discipline"]}\n"
    dat << "# code=#{metadata["code"]}\n"
    dat << "# overall_integral=#{overall_integral}\n\n"

    ordered_keys = %w[
      pair_number
      content
      time
      cost
      grade
      science
      complexity
      practice
      assimilation
      activity
      interest
      integral
    ]

    dat << ordered_keys.join("\t") << "\n"
    normalized_rows.each do |row|
      dat << ordered_keys.map { |k| row[k] }.join("\t") << "\n"
    end

    send_data dat,
              filename: "subject_pairs_results.dat",
              type: "application/octet-stream"

  else
    redirect_to root_path(anchor: "subject-pairs-section"), alert: "Невідомий тип експорту."
  end
end

  private

  def build_results_pdf(normalized:, integral:, chart_data:)
    require "prawn"
    require "prawn/table"
    require "net/http"
    require "json"
    require "uri"
    require "tempfile"

    font_dir = Rails.root.join("app", "assets", "fonts")
    regular  = font_dir.join("DejaVuSans.ttf")
    bold     = font_dir.join("DejaVuSans-Bold.ttf")

    Prawn::Document.new(page_size: "A4", margin: 36) do |pdf|
      pdf.font_families.update(
        "DejaVu" => { normal: regular.to_s, bold: bold.to_s }
      )
      pdf.font("DejaVu")

      pdf.text "Звіт: Оцінювання якості e-навчання", size: 16, style: :bold
      pdf.move_down 8
      pdf.text "Дата: #{Time.zone.now.strftime("%d.%m.%Y %H:%M")}", size: 10
      pdf.move_down 12

      pdf.text "Інтегральний показник якості", size: 12, style: :bold
      pdf.move_down 6
      pdf.text "D = #{integral}", size: 14, style: :bold
      pdf.move_down 12

      pdf.text "Нормалізовані показники", size: 12, style: :bold
      pdf.move_down 8

      headers = normalized.first&.keys || []
      header_row = headers.map { |k| INDICATOR_NAMES[k] || k }

      table_data = [header_row]
      normalized.each do |row|
        table_data << headers.map { |k| row[k].to_f.round(3) }
      end

      pdf.table(table_data, header: true, width: pdf.bounds.width) do
        row(0).font_style = :bold
        row(0).size = 9
        cells.size = 8
        cells.padding = 4
        cells.border_width = 0.5
      end

      pdf.move_down 16
      pdf.text "Візуалізація", size: 12, style: :bold
      pdf.move_down 8

      labels = (chart_data || {}).keys
      values = (chart_data || {}).values.map { |v| v.to_f }

      begin
        bar_png  = quickchart_png(build_bar_chart_config(labels, values), width: 1000, height: 360)
        line_png = quickchart_png(build_line_chart_config(labels, values), width: 1000, height: 360)

        Tempfile.create(["chart-bar", ".png"]) do |f|
          f.binmode
          f.write(bar_png)
          f.flush
          pdf.image f.path, width: pdf.bounds.width
        end

        pdf.move_down 12

        Tempfile.create(["chart-line", ".png"]) do |f|
          f.binmode
          f.write(line_png)
          f.flush
          pdf.image f.path, width: pdf.bounds.width
        end
      rescue => e
        Rails.logger.warn("[PDF] charts skipped: #{e.class}: #{e.message}")
        pdf.text "Графіки тимчасово недоступні (помилка генерації).", size: 10
      end
    end.render
  end

  def csv_file?(file)
    return false if file.nil?

    filename = file.original_filename.to_s.downcase
    ext_ok = filename.end_with?(".csv")

    type = file.content_type.to_s.downcase
    type_ok = type.include?("csv") || type.include?("text/plain") || type.include?("application/vnd.ms-excel")

    begin
      head = file.read(4096)
      file.rewind

      rows = CSV.parse(head)
      looks_like_csv = rows.any? { |r| r.is_a?(Array) && r.compact.size >= 2 }
    rescue
      looks_like_csv = false
    end

    ext_ok && (type_ok || looks_like_csv)
  end

  def quickchart_png(chart_config, width: 900, height: 350)
    uri = URI("https://quickchart.io/chart")
    payload = {
      width: width,
      height: height,
      format: "png",
      backgroundColor: "white",
      chart: chart_config
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10
    http.open_timeout = 5

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = payload.to_json

    res = http.request(req)
    raise "QuickChart error #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    res.body
  end

  def build_bar_chart_config(labels, values)
    {
      type: "bar",
      data: {
        labels: labels,
        datasets: [{
          label: "Середні значення",
          data: values
        }]
      },
      options: {
        plugins: {
          legend: { display: false },
          title: { display: true, text: "Середні значення показників" }
        },
        scales: {
          y: { beginAtZero: true, suggestedMax: 1 }
        }
      }
    }
  end

  def build_line_chart_config(labels, values)
    {
      type: "line",
      data: {
        labels: labels,
        datasets: [{
          label: "Динаміка",
          data: values,
          fill: false,
          tension: 0.25
        }]
      },
      options: {
        plugins: {
          legend: { display: false },
          title: { display: true, text: "Динаміка показників" }
        },
        scales: {
          y: { beginAtZero: true, suggestedMax: 1 }
        }
      }
    }
  end

def build_subject_pairs_results_pdf(metadata:, normalized_rows:, overall_integral:)
  require "prawn"
  require "prawn/table"
  require "tempfile"
  require "net/http"
  require "json"
  require "uri"

  font_dir = Rails.root.join("app", "assets", "fonts")
  regular  = font_dir.join("DejaVuSans.ttf")
  bold     = font_dir.join("DejaVuSans-Bold.ttf")

  Prawn::Document.new(page_size: "A4", margin: 36) do |pdf|
    pdf.font_families.update(
      "DejaVu" => { normal: regular.to_s, bold: bold.to_s }
    )
    pdf.font("DejaVu")

    pdf.text "Звіт: Розрахунок інтегрального показника якості для 5 пар дисципліни", size: 15, style: :bold
    pdf.move_down 8
    pdf.text "Дата: #{Time.zone.now.strftime("%d.%m.%Y %H:%M")}", size: 10
    pdf.move_down 12

    pdf.text "Дані дисципліни", size: 12, style: :bold
    pdf.move_down 6
    pdf.text "Факультет: #{metadata["faculty"]}"
    pdf.text "Спеціальність: #{metadata["specialty"]}"
    pdf.text "Семестр: #{metadata["semester"]}"
    pdf.text "Група: #{metadata["group_name"]}"
    pdf.text "Назва дисципліни: #{metadata["discipline"]}"
    pdf.text "Шифр: #{metadata["code"]}"
    pdf.move_down 12

    pdf.text "Інтегральний показник якості", size: 12, style: :bold
    pdf.move_down 6
    pdf.text "D = #{overall_integral}", size: 14, style: :bold
    pdf.move_down 12

    pdf.text "Нормалізовані показники для 5 пар", size: 12, style: :bold
    pdf.move_down 8

    # Порядок колонок такий самий, як на сайті
    ordered_keys = %w[
      pair_number
      content
      time
      cost
      grade
      science
      complexity
      practice
      assimilation
      activity
      interest
      integral
    ]

    header_row = [
      "Пара",
      "Змістовність",
      "Часові витрати",
      "Ресурсні витрати",
      "Успішність",
      "Науковість",
      "Складність",
      "Практична спрямованість",
      "Засвоєння",
      "Активність",
      "Зацікавленість",
      "Інтегральний"
    ]

    table_data = [header_row]
    normalized_rows.each do |row|
      table_data << ordered_keys.map do |key|
        value = row[key]
        value.is_a?(Numeric) ? value.round(4) : value
      end
    end

    pdf.table(table_data, header: true, width: pdf.bounds.width) do
      row(0).font_style = :bold
      row(0).size = 7
      cells.size = 6
      cells.padding = 3
      cells.border_width = 0.5
    end

    # ====== Графік у PDF ======
pdf.move_down 16
pdf.text "Візуалізація результатів", size: 12, style: :bold
pdf.move_down 8

labels = normalized_rows.map { |row| "Пара #{row["pair_number"]}" }
values = normalized_rows.map { |row| row["integral"].to_f.round(4) }

begin
  chart_png = quickchart_png(
    build_subject_pairs_chart_config(labels, values),
    width: 1000,
    height: 420
  )

  Tempfile.create(["subject-pairs-chart", ".png"]) do |f|
    f.binmode
    f.write(chart_png)
    f.flush
    pdf.image f.path, width: pdf.bounds.width
  end
rescue => e
  Rails.logger.warn("[PDF][SUBJECT_PAIRS] chart skipped: #{e.class}: #{e.message}")
  pdf.text "Графік тимчасово недоступний (помилка генерації).", size: 10
end
  end.render
end

def build_subject_pairs_chart_config(labels, values)
  {
    type: "bar",
    data: {
      labels: labels,
      datasets: [{
        label: "Інтегральний показник",
        data: values
      }]
    },
    options: {
      responsive: true,
      plugins: {
        legend: { display: false },
        title: {
          display: true,
          text: "Інтегральний показник якості для 5 пар"
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          suggestedMax: 1
        }
      }
    }
  }
end

end