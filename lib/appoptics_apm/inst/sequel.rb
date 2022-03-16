# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

module AppOpticsAPM
  module Inst
    ##
    # AppOpticsAPM::Inst::Sequel
    #
    # The common (shared) methods used by the AppOpticsAPM Sequel instrumentation
    # across multiple modules/classes.
    #
    module Sequel
      ##
      # assign_kvs
      #
      # Given SQL and the options hash, this method extracts the interesting
      # bits for reporting to the AppOptics dashboard.
      #
      # kvs is a hash and we are taking advantage of using it by reference to
      # assign kvs to the exit event (important for trace injection)
      #
      def assign_kvs(sql, opts, kvs)
        if !sql.is_a?(String)
          kvs[:IsPreparedStatement] = true
        end

        if ::Sequel::VERSION > '4.36.0' && !sql.is_a?(String)
          # TODO check if this is true for all sql
          # In 4.37.0, sql was converted to a prepared statement object
          sql = sql.prepared_sql unless sql.is_a?(Symbol)
        end

        if AppOpticsAPM::Config[:sanitize_sql]
          # Sanitize SQL and don't report binds
          if sql.is_a?(Symbol)
            kvs[:Query] = sql
          else
            kvs[:Query] = AppOpticsAPM::Util.sanitize_sql(sql)
          end
        else
          # Report raw SQL and any binds if they exist
          kvs[:Query] = sql.to_s
          kvs[:QueryArgs] = opts[:arguments] if opts.is_a?(Hash) && opts.key?(:arguments)
        end

        kvs[:Backtrace] = AppOpticsAPM::API.backtrace if AppOpticsAPM::Config[:sequel][:collect_backtraces]

        if ::Sequel::VERSION < '3.41.0' && !(self.class.to_s =~ /Dataset$/)
          db_opts = @opts
        elsif @pool
          db_opts = @pool.db.opts
        else
          db_opts = @db.opts
        end

        kvs[:Database]   = db_opts[:database]
        kvs[:RemoteHost] = db_opts[:host]
        kvs[:RemotePort] = db_opts[:port] if db_opts.key?(:port)
        kvs[:Flavor]     = db_opts[:adapter]
      rescue => e
        AppOpticsAPM.logger.debug "[appoptics_apm/debug Error capturing Sequel KVs: #{e.message}" if AppOpticsAPM::Config[:verbose]
      end

      ##
      # exec_with_appoptics
      #
      # This method wraps and routes the call to the specified
      # original method call
      #
      def exec_with_appoptics(method, sql, opts = ::Sequel::OPTS, &block)
        kvs = {}
        AppOpticsAPM::SDK.trace(:sequel, kvs: kvs) do
          # puts "in exec_with_appoptics: sql is a #{sql.class}, Symbol? #{sql.is_a?(Symbol)} ArgumentMapper? #{sql.is_a?(::Sequel::Dataset::ArgumentMapper)}"
          puts "in exec_with_appoptics: self is a #{self.class}"

          new_sql = add_traceparent(sql)
          assign_kvs(new_sql, opts, kvs) if AppOpticsAPM.tracing?
          send(method, new_sql, opts, &block)
        end
      end

      def add_traceparent(sql)
        # puts "............. in add_traceparent: sql is a #{sql.class}"
        # check if works needs to be done before messing with the
        # queries and prepared statements
        if AppOpticsAPM.tracing? && AppOpticsAPM::Config[:tag_sql]
          # require 'byebug'
          # byebug
          case sql
          when String
            return AppOpticsAPM::SDK.current_trace_info.add_traceparent_to_sql(sql)
          when Symbol # && self.is_a?(::Sequel::Mysql2::Database)
            # TODO this does not work for postgresql
            ps = prepared_statement(sql)
            new_ps = add_traceparent_to_ps(ps)
            set_prepared_statement(sql, new_ps)
            return sql # related query may have been modified
          when ::Sequel::Dataset::ArgumentMapper
            new_sql = add_traceparent_to_ps(sql)
            return new_sql # related query may have been modified
          end
        end
        sql
      end

      # this method uses some non-api methods partially copied from
      # `execute_prepared_statement` in `mysql2.rb`
      # and `prepare` in `prepared_statements.rb` in the sequel gem
      def add_traceparent_to_ps(ps)
        sql = ps.prepared_sql
        new_sql = AppOpticsAPM::SDK.current_trace_info.add_traceparent_to_sql(sql)

        unless new_sql == sql
          new_ps = ps.clone(:prepared_sql=>new_sql, :sql=>new_sql)
          return new_ps
        end

        ps # no change, no trace context added
      end
    end

    module SequelDatabase
      include AppOpticsAPM::Inst::Sequel

      def self.included(klass)
        AppOpticsAPM::Util.method_alias(klass, :run, ::Sequel::Database)
        AppOpticsAPM::Util.method_alias(klass, :execute_ddl, ::Sequel::Database)
        AppOpticsAPM::Util.method_alias(klass, :execute_dui, ::Sequel::Database)
        AppOpticsAPM::Util.method_alias(klass, :execute_insert, ::Sequel::Database)
      end

      def run_with_appoptics(sql, opts = ::Sequel::OPTS)
        kvs = {}
        AppOpticsAPM::SDK.trace(:sequel, kvs: kvs) do
          puts "in run_with_appoptics: sql is a #{sql.class}, ArgumentMapper? #{sql.is_a?(::Sequel::Dataset::ArgumentMapper)}"

          new_sql = add_traceparent(sql)
          kvs = assign_kvs(new_sql, opts, kvs) if AppOpticsAPM.tracing?
          run_without_appoptics(new_sql, opts)
        end
      end

      def execute_ddl_with_appoptics(sql, opts = ::Sequel::OPTS, &block)
        # If we're already tracing a sequel operation, then this call likely came
        # from Sequel::Dataset.  In this case, just pass it on.
        return execute_ddl_without_appoptics(sql, opts, &block) if AppOpticsAPM.tracing_layer?(:sequel)

        exec_with_appoptics(:execute_ddl_without_appoptics, sql, opts, &block)
      end

      def execute_dui_with_appoptics(sql, opts = ::Sequel::OPTS, &block)
        # If we're already tracing a sequel operation, then this call likely came
        # from Sequel::Dataset.  In this case, just pass it on.
        return execute_dui_without_appoptics(sql, opts, &block) if AppOpticsAPM.tracing_layer?(:sequel)

        exec_with_appoptics(:execute_dui_without_appoptics, sql, opts, &block)
      end

      def execute_insert_with_appoptics(sql, opts = ::Sequel::OPTS, &block)
        # If we're already tracing a sequel operation, then this call likely came
        # from Sequel::Dataset.  In this case, just pass it on.
        return execute_insert_without_appoptics(sql, opts, &block) if AppOpticsAPM.tracing_layer?(:sequel)

        exec_with_appoptics(:execute_insert_without_appoptics, sql, opts, &block)
      end
    end # module SequelDatabase

    module MySQLSequelDatabase
      include AppOpticsAPM::Inst::Sequel

      def self.included(klass)
        AppOpticsAPM::Util.method_alias(klass, :execute, ::Sequel::MySQL::MysqlMysql2::DatabaseMethods)
      end

      def execute_with_appoptics(*args, &block)
        # if this is called via a dataset it is already being traced
        return execute_without_appoptics(*args, &block) if AppOpticsAPM.tracing_layer?(:sequel)

        kvs = {}
        AppOpticsAPM::SDK.trace(:sequel, kvs: kvs) do
          #   puts "in mysql execute: sql is a #{args[0].class}, ArgumentMapper? #{args[0].is_a?(::Sequel::Dataset::ArgumentMapper)}"
          puts "%%%%%% in mysql execute: self is a #{self.class}"
          puts "#{args[0]}"

          new_sql = add_traceparent(args[0])
          args[0] = new_sql
          kvs = assign_kvs(args[0], args[1], kvs) if AppOpticsAPM.tracing?
          execute_without_appoptics(*args, &block)
        end
      end
    end

    module PGSequelDatabase
      include AppOpticsAPM::Inst::Sequel

      def self.included(klass)
        AppOpticsAPM::Util.method_alias(klass, :execute, ::Sequel::Postgres::Database)
      end

      def execute_with_appoptics(*args, &block)
        return execute_without_appoptics(*args, &block) if AppOpticsAPM.tracing_layer?(:sequel)

        kvs = {}
        # AppOpticsAPM::SDK.trace(:sequel, kvs: kvs) do
        puts "###### in pg execute: sql is a #{args[0].class}" unless args[0].is_a?(String)
        puts "$$$$$$$$$$ in pg execute self is a #{self.class}"

        # new_sql = add_traceparent(args[0])
        # args[0] = new_sql
        kvs = assign_kvs(args[0], args[1], kvs) if AppOpticsAPM.tracing?
        execute_without_appoptics(*args, &block)
        # end
      end
    end

    module SequelDataset
      include AppOpticsAPM::Inst::Sequel

      def self.included(klass)
        AppOpticsAPM::Util.method_alias(klass, :execute, ::Sequel::Dataset)
        AppOpticsAPM::Util.method_alias(klass, :execute_ddl, ::Sequel::Dataset)
        AppOpticsAPM::Util.method_alias(klass, :execute_dui, ::Sequel::Dataset)
        AppOpticsAPM::Util.method_alias(klass, :execute_insert, ::Sequel::Dataset)
      end

      def execute_with_appoptics(sql, opts = ::Sequel::OPTS, &block)
        exec_with_appoptics(:execute_without_appoptics, sql, opts, &block)
      end

      def execute_ddl_with_appoptics(sql, opts = ::Sequel::OPTS, &block)
        exec_with_appoptics(:execute_ddl_without_appoptics, sql, opts, &block)
      end

      def execute_dui_with_appoptics(sql, opts = ::Sequel::OPTS, &block)
        exec_with_appoptics(:execute_dui_without_appoptics, sql, opts, &block)
      end

      def execute_insert_with_appoptics(sql, opts = ::Sequel::OPTS, &block)
        exec_with_appoptics(:execute_insert_without_appoptics, sql, opts, &block)
      end

    end # module SequelDataset
  end # module Inst
end # module AppOpticsAPM

if AppOpticsAPM::Config[:sequel][:enabled]
  if defined?(::Sequel) && ::Sequel::VERSION < '4.0.0'
    # For versions before 4.0.0, Sequel::OPTS wasn't defined.
    # Define it as an empty hash for backwards compatibility.
    module ::Sequel
      OPTS = {}
    end
  end

  if defined?(::Sequel)
    AppOpticsAPM.logger.info '[appoptics_apm/loading] Instrumenting sequel' if AppOpticsAPM::Config[:verbose]
    AppOpticsAPM::Util.send_include(::Sequel::Database, AppOpticsAPM::Inst::SequelDatabase)
    AppOpticsAPM::Util.send_include(::Sequel::Dataset, AppOpticsAPM::Inst::SequelDataset)

    # TODO this is temporary, we need to instrument `require`, see NH-9711
    require 'sequel/adapters/mysql2'
    AppOpticsAPM::Util.send_include(::Sequel::MySQL::MysqlMysql2::DatabaseMethods, AppOpticsAPM::Inst::MySQLSequelDatabase)
    require 'sequel/adapters/postgres'
    AppOpticsAPM::Util.send_include(::Sequel::Postgres::Database, AppOpticsAPM::Inst::PGSequelDatabase)
  end
end
