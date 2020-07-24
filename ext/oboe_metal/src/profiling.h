
#ifndef PROFILING_H
#define PROFILING_H

#include <ruby/ruby.h>
#include <ruby/intern.h>
#include <ruby/debug.h>
#include <signal.h>
#include <sys/time.h>
#include <string>
#include <unordered_map>
#include <thread>

#include "oboe.hpp"

#define FP_ENABLE true
#include "function_profiler.hpp"

#include <boost/thread/thread.hpp>
#include <boost/lockfree/spsc_queue.hpp>
// #include <boost/date_time/posix_time/posix_time.hpp>
// #include <boost/atomic.hpp>

oboe_metadata_t *md;

#define BUF_SIZE 2048

#define FP_ENABLE true
#include "function_profiler.hpp"

using namespace std;

#if !defined(AO_GETTID)
     #if defined(_WIN32)
        #define AO_GETTID GetCurrentThreadId
     #else
        #include <unistd.h>
        #include <sys/syscall.h>
        #ifdef SYS_gettid
           #define AO_GETTID syscall(SYS_gettid);
        #endif
     #endif
#endif

typedef struct msg {
   VALUE frames_buffer[BUF_SIZE];
   int num;
   pid_t tid;
   long ts;
   string xtrace;
} msg_t;

class Profiling {
   public:
    static void profiler_record_frames(void *data);
    static void process_snapshot(VALUE* frames_buffer,
                                 int num,
                                 pid_t tid,
                                 long ts);
    static void profiler_signal_handler(int sigint,
                                        siginfo_t* siginfo,
                                        void* ucontext);
    static VALUE profiling_start(pid_t tid);
    static VALUE profiling_stop(pid_t tid);
    static VALUE profiling_run(VALUE self);
    static VALUE profiling_running_p(VALUE self);
    static VALUE get_interval(VALUE self);
    static VALUE set_interval(int argc, VALUE* argv, VALUE self);
   //  static VALUE set_app_root(int, VALUE*, VALUE);
};

extern "C" void Init_profiling(void);

class Processing {
   public:
    static void consumer();
    static void process(msg_t message);
};

#endif // PROFILING_H