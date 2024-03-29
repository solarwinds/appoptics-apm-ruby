# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

require 'minitest_helper'
require 'mocha/minitest'

require 'rack/test'
require 'rack/lobster'
require 'solarwinds_apm/inst/rack'

class TyphoeusMockedTest < Minitest::Test

  include Rack::Test::Methods

  def app
    @app = Rack::Builder.new {
      # use Rack::CommonLogger
      # use Rack::ShowExceptions
      use SolarWindsAPM::Rack
      map "/out" do
        run Proc.new {
          req = Typhoeus::Request.new("http://127.0.0.2:8101/", { :method => :get })
          req.run
          [200,
           { "Content-Type" => "text/html" },
           [req.options[:headers]['traceparent'], req.options[:headers]['tracestate']]]
        }
      end
    }
  end

  def setup
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!

    @sample_rate = SolarWindsAPM::Config[:sample_rate]
    @tracing_mode = SolarWindsAPM::Config[:tracing_mode]

    SolarWindsAPM::Config[:sample_rate] = 1000000
    SolarWindsAPM::Config[:tracing_mode] = :enabled

    SolarWindsAPM.trace_context = nil
    SolarWindsAPM::Context.clear
  end

  def teardown
    SolarWindsAPM::Config[:sample_rate] = @sample_rate
    SolarWindsAPM::Config[:tracing_mode] = @tracing_mode
  end

  ############# Typhoeus::Request ##############################################

  def test_tracing_sampling
    SolarWindsAPM::SDK.start_trace('typhoeus_tests') do
      request = Typhoeus::Request.new("http://127.0.0.2:8101/", { :method => :get })
      request.run
      assert_trace_headers(request.options[:headers])
    end

    refute SolarWindsAPM::Context.isValid
  end

  def test_tracing_not_sampling
    SolarWindsAPM.config_lock.synchronize do
      SolarWindsAPM::Config[:sample_rate] = 0
      SolarWindsAPM::SDK.start_trace('typhoeus_tests') do
        request = Typhoeus::Request.new("http://127.0.0.1:8101/", { :method => :get })
        request.run

        assert_trace_headers(request.options[:headers], false)
      end
    end
    refute SolarWindsAPM::Context.isValid
  end

  def test_no_xtrace
    request = Typhoeus::Request.new("http://127.0.0.1:8101/", { :method => :get })
    request.run

    refute request.options[:headers]['traceparent']
    refute SolarWindsAPM::Context.isValid
  end

  def test_preserves_custom_headers
    SolarWindsAPM::SDK.start_trace('typhoeus_tests') do
      request = Typhoeus::Request.new('http://127.0.0.6:8101', headers: { 'Custom' => 'specialvalue' }, :method => :get)
      request.run

      assert request.options[:headers]['Custom']
      assert_match /specialvalue/, request.options[:headers]['Custom']
    end
    refute SolarWindsAPM::Context.isValid
  end

  ############# Typhoeus::Hydra ##############################################

  def test_hydra_tracing_sampling
    SolarWindsAPM::SDK.start_trace('typhoeus_tests') do
      hydra = Typhoeus::Hydra.hydra
      request_1 = Typhoeus::Request.new("http://127.0.0.2:8101/", { :method => :get })
      request_2 = Typhoeus::Request.new("http://127.0.0.2:8101/counting_sheep", { :method => :get })
      hydra.queue(request_1)
      hydra.queue(request_2)
      hydra.run

      assert_trace_headers(request_1.options[:headers], true)
      assert_trace_headers(request_2.options[:headers], true)
    end
    refute SolarWindsAPM::Context.isValid
  end

  def test_hydra_tracing_not_sampling
    SolarWindsAPM.config_lock.synchronize do
      SolarWindsAPM::Config[:sample_rate] = 0
      SolarWindsAPM::SDK.start_trace('typhoeus_tests') do
        hydra = Typhoeus::Hydra.hydra
        request_1 = Typhoeus::Request.new("http://127.0.0.2:8101/", { :method => :get })
        request_2 = Typhoeus::Request.new("http://127.0.0.2:8101/counting_sheep", { :method => :get })
        hydra.queue(request_1)
        hydra.queue(request_2)
        hydra.run

        assert_trace_headers(request_1.options[:headers], false)
        assert_trace_headers(request_2.options[:headers], false)
      end
    end
    refute SolarWindsAPM::Context.isValid
  end

  def test_hydra_no_xtrace
    hydra = Typhoeus::Hydra.hydra
    request_1 = Typhoeus::Request.new("http://127.0.0.2:8101/", { :method => :get })
    request_2 = Typhoeus::Request.new("http://127.0.0.2:8101/counting_sheep", { :method => :get })
    hydra.queue(request_1)
    hydra.queue(request_2)
    hydra.run

    refute request_1.options[:headers]['traceparent'], "There should not be an traceparent header, #{request_1.options[:headers]['traceparent']}"
    refute request_2.options[:headers]['traceparent'], "There should not be an traceparent header, #{request_2.options[:headers]['traceparent']}"
    refute SolarWindsAPM::Context.isValid
  end

  def test_hydra_preserves_custom_headers
    SolarWindsAPM::SDK.start_trace('typhoeus_tests') do
      hydra = Typhoeus::Hydra.hydra
      request = Typhoeus::Request.new('http://127.0.0.6:8101', headers: { 'Custom' => 'specialvalue' }, :method => :get)
      hydra.queue(request)
      hydra.run

      assert request.options[:headers]['Custom']
      assert_match /specialvalue/, request.options[:headers]['Custom']
    end
    refute SolarWindsAPM::Context.isValid
  end

  ##### W3C tracestate propagation

  def test_propagation_simple_trace_state
    task_id = 'a462ade6cfe479081764cc476aa9831b'
    trace_id = "00-#{task_id}-cb3468da6f06eefc-01"
    state = 'sw=cb3468da6f06eefc-01'
    headers = { traceparent: trace_id, tracestate: state }
    SolarWindsAPM.trace_context = SolarWindsAPM::TraceContext.new(headers)

    request = Typhoeus::Request.new("http://127.0.0.1:8101/", { :method => :get })
    SolarWindsAPM::SDK.start_trace('typhoeus_tests', headers: headers) do
      request.run
    end

    assert_trace_headers(request.options[:headers], true)
    assert_equal task_id, SolarWindsAPM::TraceString.trace_id(request.options[:headers]['traceparent'])
    refute_equal state, request.options[:headers]['tracestate']

    refute SolarWindsAPM::Context.isValid
  end

  def test_propagation_simple_trace_state_not_tracing
    SolarWindsAPM::Config[:tracing_mode] = :disabled

    task_id = 'a462ade6cfe479081764cc476aa9831b'
    trace_id = "00-#{task_id}-cb3468da6f06eefc-01"
    state = 'sw=cb3468da6f06eefc-01'
    headers = { traceparent: trace_id, tracestate: state }
    SolarWindsAPM.trace_context = SolarWindsAPM::TraceContext.new(headers)

    request = Typhoeus::Request.new("http://127.0.0.1:8101/", { :method => :get })
    request.run

    assert_equal trace_id, request.options[:headers]['traceparent']
    assert_equal state, request.options[:headers]['tracestate']

    refute SolarWindsAPM::Context.isValid
  end

  def test_propagation_multimember_trace_state
    task_id = 'a462ade6cfe479081764cc476aa9831b'
    trace_id = "00-#{task_id}-cb3468da6f06eefc-01"
    state = 'aa= 1234, sw=cb3468da6f06eefc-01,%%cc=%%%45'
    headers = { traceparent: trace_id, tracestate: state }

    request = Typhoeus::Request.new("http://127.0.0.1:8101/", { :method => :get })
    SolarWindsAPM::SDK.start_trace('typhoeus_tests', headers: headers) do
      request.run
    end

    assert_trace_headers(request.options[:headers], true)
    assert_equal task_id, SolarWindsAPM::TraceString.trace_id(request.options[:headers]['traceparent'])
    assert_equal "sw=#{SolarWindsAPM::TraceString.span_id_flags(request.options[:headers]['traceparent'])},aa= 1234,%%cc=%%%45",
                 request.options[:headers]['tracestate']

    refute SolarWindsAPM::Context.isValid
  end

  def test_propagation_hydra_tracing_not_sampling
    SolarWindsAPM::Config[:tracing_mode] = :disabled

    task_id = 'a462ade6cfe479081764cc476aa9831b'
    trace_id = "00-#{task_id}-cb3468da6f06eefc-01"
    state = 'aa= 1234, sw=cb3468da6f06eefc-01,%%cc=%%%45'
    headers = { traceparent: trace_id, tracestate: state }
    SolarWindsAPM.trace_context = SolarWindsAPM::TraceContext.new(headers)

    hydra = Typhoeus::Hydra.hydra
    request_1 = Typhoeus::Request.new("http://127.0.0.2:8101/", { :method => :get })
    request_2 = Typhoeus::Request.new("http://127.0.0.2:8101/counting_sheep", { :method => :get })
    hydra.queue(request_1)
    hydra.queue(request_2)
    hydra.run

    assert_equal trace_id, request_1.options[:headers]['traceparent']
    assert_equal state, request_1.options[:headers]['tracestate']

    assert_equal trace_id, request_2.options[:headers]['traceparent']
    assert_equal state, request_2.options[:headers]['tracestate']

    refute SolarWindsAPM::Context.isValid
  end

end
