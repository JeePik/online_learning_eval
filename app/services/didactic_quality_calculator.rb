class DidacticQualityCalculator
def harrington(x)
a = -2.0
b = 5.0
Math.exp(-Math.exp(a - b * x))
end


def initialize(data)
@data = data
end


# Normalize to [0,1] and apply Harrington scale
def normalized_indicators
@normalized ||= @data.map do |row|
row.transform_values do |value|
v = normalize(value)
harrington(v)
end
end
end


# Integral index (Formula 2.22)
def integral_index
values = normalized_indicators.flat_map(&:values)
n = values.size
product = values.reduce(1.0) { |p, v| p * v }


(product**(1.0 / n)).round(4)
end


# Data for visualization
def chart_data
avg = {}


normalized_indicators.each do |row|
row.each do |k, v|
avg[k] ||= []
avg[k] << v
end
end


avg.transform_values do |vals|
(vals.sum / vals.size).round(3)
end
end


private


def normalize(x)
min = 0.0
max = 100.0


v = (x - min) / (max - min)
[[v, 0].max, 1].min
end
end