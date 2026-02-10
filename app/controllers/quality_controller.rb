require "csv"
require "prawn"
require "prawn/table"



class QualityController < ApplicationController


def index
end


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


def calculate
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

      chart_data = Rails.cache.read("dq:#{cache_key}:chart_data") || {}
      pdf_data = build_results_pdf(normalized: normalized, integral: integral, chart_data: chart_data)


      format.pdf do
        pdf_data = build_results_pdf(normalized: normalized, integral: integral, chart_data: chart_data)
        send_data pdf_data,
                  filename: "results.pdf",
                  type: "application/pdf",
                  disposition: "inline"
      end
    end
    return

  else
    redirect_to root_path, alert: "Невідомий тип завантаження"
    return
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
    pdf.font("DejaVu") # кирилиця ок

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

    # ========= ГРАФІКИ =========
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




private

def csv_file?(file)
  return false if file.nil?

  filename = file.original_filename.to_s.downcase
  ext_ok = filename.end_with?(".csv")

  type = file.content_type.to_s.downcase
  type_ok = type.include?("csv") || type.include?("text/plain") || type.include?("application/vnd.ms-excel")

  # Мінімальна перевірка “схоже на CSV”: файл парситься і має хоча б 1 рядок з 2+ полями
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

#---------малюю_графіки_в_png_для_pdf----------------

require "net/http"
require "json"
require "uri"

private

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

  res.body # binary PNG
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
#---------Кінець----------------

end