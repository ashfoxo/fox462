pragma Singleton

// The notification daemon (replaces mako). Every notification pops up
// top-right for a few seconds; critical ones stay until clicked. Chat apps'
// notifications (scratchpads.nix) are also kept in the bar's chat menu
// until you press clear there. Do not disturb stops the popups but not the
// chat menu, and critical ones still pop up.
//
// To see what an app's notifications look like (for the `notify` and
// `notifyBody` fields in scratchpads.nix):
//   journalctl --user -u quickshell -f | grep notification
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    property bool dnd: false

    // Showing now, oldest first. Each: { id, n, app, chat, summary, body, critical, time }
    property var popups: []
    // Chat messages, newest first: the same fields, minus `n` (the app
    // can close a notification, the copy here stays until you clear).
    property var chats: []

    // Ticks every 30s so "2m" labels move on.
    property real now: Date.now()

    function unread(padName) {
        return chats.filter(m => m.chat === padName).length;
    }
    function clear() {
        chats = [];
    }

    function chatPadFor(n) {
        return Pads.chats.find(p =>
            (p.notify && new RegExp(p.notify, "i").test(`${n.appName} ${n.desktopEntry}`))
            || (p.notifyBody && new RegExp(p.notifyBody, "i").test(n.body))) ?? null;
    }

    // Plain text for the popups: no markup, no "messages.google.com" line
    // that Chromium puts first for web apps.
    function plain(s) {
        return s.replace(/<[^>]*>/g, "")
            .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
            .replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&");
    }
    function bodyFor(n, pad) {
        let lines = plain(n.body).split("\n");
        if (pad?.notifyBody && new RegExp(pad.notifyBody, "i").test(lines[0]))
            lines = lines.slice(1);
        return lines.join(" ").trim();
    }

    function receive(n) {
        const pad = chatPadFor(n);
        console.log(`notification from app "${n.appName}" (desktop entry "${n.desktopEntry}"): ${pad ? (Pads.quiet(pad) ? `chat ${pad.name}, dropped (just started)` : `chat ${pad.name}`) : "not a chat app"}`);
        if (pad && Pads.quiet(pad))
            return;  // left untracked, so the server drops it

        n.tracked = true;
        const m = {
            id: n.id,
            app: pad ? pad.name : (n.appName || "notification").toLowerCase(),
            chat: pad ? pad.name : "",
            summary: plain(n.summary),
            body: bodyFor(n, pad),
            critical: n.urgency === NotificationUrgency.Critical,
            time: Date.now()
        };

        if (pad)
            chats = [Object.assign({}, m)].concat(chats).slice(0, Config.notifications.keep);

        if (dnd && !m.critical) {
            // Nothing to show; chat ones are in the menu already.
            n.expire();
            return;
        }

        m.n = n;
        n.closed.connect(() => root.popups = root.popups.filter(p => p.n !== n));
        let next = popups.filter(p => p.id !== m.id).concat([m]);
        // Too many: the oldest non-critical ones go first.
        while (next.length > Config.notifications.maxPopups) {
            const old = next.find(p => !p.critical) ?? next[0];
            next = next.filter(p => p !== old);
            old.n.expire();
        }
        popups = next;
    }

    // "now", "2m", "1h"
    function age(m) {
        const s = (now - m.time) / 1000;
        return s < 60 ? "now" : Fmt.duration(s);
    }

    // Clicking a popup: chat apps' scratchpad comes up, and the app's own
    // default action runs if it has one (usually: open that conversation).
    // Then it closes.
    function activate(m) {
        if (m.chat)
            Pads.show(Pads.find(m.chat));
        const action = m.n.actions.find(a => a.identifier === "default");
        if (action)
            action.invoke();
        m.n.dismiss();
    }

    NotificationServer {
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        persistenceSupported: true
        keepOnReload: false
        onNotification: n => root.receive(n)
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }
}
