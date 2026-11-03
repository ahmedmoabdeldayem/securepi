/*
 * securepi-logger: minimal telemetry stub
 *
 * SELinux-confined reference service. Reads /etc/securepi-logger.conf,
 * samples /proc/uptime, appends a timestamped line to /run/securepi-logger.log.
 *
 * Intentionally a compiled binary so SELinux domain transitions fire on exec()
 * (shell scripts transition on the interpreter, not the script file).
 */
#include <stdio.h>
#include <time.h>
#include <unistd.h>

#define CONF    "/etc/securepi-logger.conf"
#define LOGFILE "/run/securepi-logger/securepi-logger.log"

int main(void)
{
    int interval = 30;
    FILE *f;

    f = fopen(CONF, "r");
    if (f) {
        int v;
        if (fscanf(f, "INTERVAL=%d", &v) == 1)
            interval = v;
        fclose(f);
    }

    for (;;) {
        double uptime = 0.0;
        time_t now = time(NULL);
        struct tm *tm_info;
        char tbuf[32];

        f = fopen("/proc/uptime", "r");
        if (f) { fscanf(f, "%lf", &uptime); fclose(f); }

        tm_info = gmtime(&now);
        strftime(tbuf, sizeof(tbuf), "%Y-%m-%dT%H:%M:%SZ", tm_info);

        f = fopen(LOGFILE, "a");
        if (f) { fprintf(f, "%s uptime=%.0f\n", tbuf, uptime); fclose(f); }

        sleep((unsigned)interval);
    }
    return 0;
}
