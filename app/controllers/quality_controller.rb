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
redirect_to root_path, alert: "Завантажте CSV-файл"
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
@integral = calculator.integral_index

raw = calculator.chart_data

@chart_data = raw.transform_keys do |k|
  INDICATOR_NAMES[k] || k
end

session[:normalized] = @normalized
session[:integral] = @integral


render :index
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