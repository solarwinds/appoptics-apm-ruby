
module TraceView
  module MethodProfiling
    def profile_wrapper(method, report_kvs, opts, *args, &block)
      report_kvs[:Backtrace] = TraceView::API.backtrace(2) if opts[:backtrace]
      report_kvs[:Arguments] = args if opts[:arguments]

      # if this is a rails controller we want to set the transaction for the outbound metrics
      if defined?(request) && defined?(request.env) && defined?(self.action_name)
        request.env['traceview.transaction'] = "#{self.class.name}.#{self.action_name}"
      end

      TraceView::API.log(nil, :profile_entry, report_kvs)

      begin
        rv = self.send(method, *args, &block)
        report_kvs[:ReturnValue] = rv if opts[:result]
        rv
      rescue => e
        TraceView::API.log_exception(nil, e)
        raise
      ensure
        report_kvs.delete(:Backtrace)
        report_kvs.delete(:Controller)
        report_kvs.delete(:Action)
        TraceView::API.log(nil, :profile_exit, report_kvs)
      end
    end
  end
end
