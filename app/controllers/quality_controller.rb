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
  file = params[:csv_file]

  if file.nil?
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Завантажте CSV-файл" }
      format.turbo_stream do
        flash.now[:alert] = "Завантажте CSV-файл"
        render turbo_stream: turbo_stream.replace("results", partial: "quality/results_empty")
      end
    end
    return
  end

  data = []
  CSV.open(file.path, headers: true) do |csv|
    csv.each do |row|
      data << row.to_h.transform_values(&:to_f)
    end
  end

  calculator = DidacticQualityCalculator.new(data)

  @normalized = calculator.normalized_indicators
  @integral   = calculator.integral_index

  raw = calculator.chart_data
  @chart_data = raw.transform_keys { |k| INDICATOR_NAMES[k] || k }

  session[:normalized] = @normalized
  session[:integral]   = @integral

  respond_to do |format|
    format.html { render :index }          # якщо хтось відправить без Turbo
    format.turbo_stream                   # буде шукати calculate.turbo_stream.erb
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
end