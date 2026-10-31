pragma Singleton

// Small text formatters shared by the dropdowns.
import QtQuick
import Quickshell

Singleton {
    // 45 -> "45s", 900 -> "15m", 7200 -> "2h", 200000 -> "2d"
    function duration(seconds) {
        const s = Math.max(0, Math.round(seconds));
        if (s < 60)
            return `${s}s`;
        if (s < 3600)
            return `${Math.floor(s / 60)}m`;
        if (s < 172800)
            return `${Math.floor(s / 3600)}h`;
        return `${Math.floor(s / 86400)}d`;
    }

    function ago(unixMs) {
        return duration((Date.now() - unixMs) / 1000) + " ago";
    }

    // "00:31"
    function time(unixMs) {
        return Qt.formatTime(new Date(unixMs), "HH:mm");
    }

    // "today 00:31", "tonight 23:10", "tomorrow 00:31", "wed 28 oct 00:31"
    function day(unixMs) {
        const d = new Date(unixMs);
        const now = new Date();
        const midnight = x => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
        const days = Math.round((midnight(d) - midnight(now)) / 86400000);
        const t = time(unixMs);
        if (days === 0)
            return (d.getHours() >= 18 ? "tonight " : "today ") + t;
        if (days === 1)
            return (d.getHours() < 5 ? "tonight " : "tomorrow ") + t;
        return d.toLocaleDateString(Qt.locale("en_US"), "ddd d MMM").toLowerCase() + " " + t;
    }
}
