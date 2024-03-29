require 'solarwinds_apm'

SolarWindsAPM::Config[:sample_rate] = 1000000 if defined? SolarWindsAPM

class Rainbow
  def self.paint
    invent_color
    add_color_to_pixel
  end

  def self.invent_color
    2.times do |i|
      mix_pigments(i)
    end
  end

  def self.add_color_to_pixel
    number_of_elements = 1_000
    randoms = Array.new(number_of_elements) { rand(10) }

    randoms.each do |num|
      num + 42
    end
  end

  def self.mix_pigments(number)
    number_of_elements = 1_000
    randoms = Array.new(number_of_elements) { rand(10) }

    randoms.each do |num|
      num + number
    end
  end
end

SolarWindsAPM::Config.profiling = :enabled if defined? SolarWindsAPM
SolarWindsAPM::Config[:profiling_interval] = 5 if defined? SolarWindsAPM

unless SolarWindsAPM::SDK.solarwinds_ready?(10_000)
  puts "aborting!!! Agent not ready after 10 seconds"
  exit false
end if defined? SolarWindsAPM

ENV['WITH_PROFILING']='true'

puts "initial: #{`ps -o rss -p #{$$}`.lines.last}"

start = Time.now

oboe_source = ENV['OBOE_LOCAL'] ? "oboe_from_branch" : "oboe_from_s3"
SolarWindsAPM::SDK.start_trace("parent_#{oboe_source}") do
  pids = []
  5.times do
    pids << fork do
      SolarWindsAPM::SDK.start_trace("child_process") do
        th = []
        3.times do
          th << Thread.new do
            if ENV['WITH_PROFILING'] == 'true'
              SolarWindsAPM::Profiling.run do
                400.times do
                  Rainbow.paint
                end
              end
            else
              400.times do
                Rainbow.paint
              end
            end
          end
        end
        th.each { |th| th.join }
      end
    end
  end
  SolarWindsAPM::SDK.trace("parent_waitall") do
    Rainbow.paint
    puts Process.waitall
    puts "trace_id: #{SolarWindsAPM::SDK.current_trace_info.trace_id}"
  end
end

puts "final: #{`ps -o rss -p #{$$}`.lines.last}"
puts "time: #{Time.now - start}"
