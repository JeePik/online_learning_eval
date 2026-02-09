require "csv"


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

  session[:normalized] = @normalized
  session[:integral]   = @integral

  respond_to do |format|
    format.html { render :index }
    format.turbo_stream
  end
end



def download
type = params[:type]


case type
when "normalized"
data = session[:normalized]
filename = "normalized.csv"
when "integral"
data = [session[:integral]]
filename = "integral.csv"
end


csv = CSV.generate do |csv|
if type == "normalized"
csv << data.first.keys
data.each { |row| csv << row.values }
else
csv << ["integral_index"]
csv << data
end
end


send_data csv, filename: filename
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



end