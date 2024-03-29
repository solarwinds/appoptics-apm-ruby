# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

#####################################################
# FYI:
# Faraday only adds tracing when it is
# not using an adapter that is instrumented
#
# otherwise we would get two spans for the same call
#####################################################

module SolarWindsAPM
  module Inst
    module FaradayConnection
      include SolarWindsAPM::SDK::TraceContextHeaders

      def run_request(method, url, body, headers, &block)
        remote_call = remote_call?
        unless SolarWindsAPM.tracing?
          if remote_call
            add_tracecontext_headers(@headers)
          end
          return super(method, url, body, headers, &block)
        end

        begin
          SolarWindsAPM::API.log_entry(:faraday)
          if remote_call # nothing else is instrumented that could add the w3c context
            add_tracecontext_headers(@headers)
          end

          result = super(method, url, body, headers, &block)

          kvs = {}

          # this seems the safer condition than trying to identify the
          # faraday version when adapter started to work without arg
          # and handlers don't include the adapter anymore
          if @builder.method(:adapter).parameters.find { |ele| ele[0] == :req }
            kvs[:Middleware] = @builder.handlers
          else
            kvs[:Middleware] = [@builder.adapter] + @builder.handlers
          end
          kvs[:Backtrace] = SolarWindsAPM::API.backtrace if SolarWindsAPM::Config[:faraday][:collect_backtraces]

          # Only send service KVs if we're not using an adapter
          # Otherwise, the adapter instrumentation will send the service KVs
          if remote_call
            kvs.merge!(rsc_kvs(url, method, result))
          end

          result
        rescue => e
          SolarWindsAPM::API.log_exception(:faraday, e)
          raise e
        ensure
          SolarWindsAPM::API.log_exit(:faraday, kvs)
        end
      end

      private

      # This is only considered a remote service call if the middleware/adapter is not instrumented
      def remote_call?
        if @builder.method(:adapter).parameters.find { |ele| ele[0] == :req }
          (@builder.handlers.map(&:name) & SW_APM_INSTR_ADAPTERS).count == 0
        else
          ((@builder.handlers.map(&:name) << @builder.adapter.name) & SW_APM_INSTR_ADAPTERS).count == 0
        end
      end

      def rsc_kvs(_url, method, result)
        kvs = { :Spec => 'rsc',
                :IsService => 1,
                :HTTPMethod => method.upcase,
                :HTTPStatus => result.status, }
        kvs[:RemoteURL] = result.env.to_hash[:url].to_s
        kvs[:RemoteURL].split('?').first unless SolarWindsAPM::Config[:faraday][:log_args]

        kvs
      end
    end
  end
end

if defined?(Faraday) && SolarWindsAPM::Config[:faraday][:enabled]
  SolarWindsAPM.logger.info '[solarwinds_apm/loading] Instrumenting faraday' if SolarWindsAPM::Config[:verbose]
  Faraday::Connection.prepend(SolarWindsAPM::Inst::FaradayConnection)

  SW_APM_INSTR_ADAPTERS = [] # ["Faraday::Adapter::NetHttp", "Faraday::Adapter::Excon", "Faraday::Adapter::Typhoeus"]

  SW_APM_INSTR_ADAPTERS << "Faraday::Adapter::Typhoeus" if defined? Faraday::Adapter::Typhoeus
  SW_APM_INSTR_ADAPTERS << "Faraday::Adapter::NetHttp" if defined? Faraday::Adapter::NetHttp
  SW_APM_INSTR_ADAPTERS << "Faraday::Adapter::Excon" if defined? Faraday::Adapter::Excon
  SW_APM_INSTR_ADAPTERS << "Faraday::Adapter::HTTPClient" if defined? Faraday::Adapter::HTTPClient
end
