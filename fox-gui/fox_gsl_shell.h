#ifndef FOX_GSL_SHELL_H
#define FOX_GSL_SHELL_H

#include <fx.h>
#include "agg_array.h"

#include "gsl_shell_thread.h"
#include "shared_vector.h"

class GslShellApp;

class fox_gsl_shell : public gsl_shell_thread
{
public:
    fox_gsl_shell(GslShellApp* app): m_app(app), m_close(0) { }

    ~fox_gsl_shell() { delete m_close; }

    virtual void init();
    virtual void close();

    virtual void before_eval();
    virtual void restart_callback();
    virtual void quit_callback();

    void set_closing_signal(FXGUISignal* s) { m_close = s; }

    void window_close_notify(int window_id);

private:
    GslShellApp* m_app;
    FXGUISignal* m_close;
    shared_vector<int> m_window_close_queue;
};

#endif
