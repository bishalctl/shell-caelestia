.pragma library

function names(values) {
    return Array.isArray(values) ? values.filter((name, index) => typeof name === "string" && name.length > 0 && values.indexOf(name) === index) : [];
}

function recent(history, name) {
    return name ? [name, ...names(history).filter(n => n !== name)] : names(history);
}

function fallback(available, history, blocked) {
    const allowed = names(available).filter(n => !blocked.includes(n));
    return names(history).find(n => allowed.includes(n)) ?? allowed[0] ?? "";
}

function musicOutput(current, available, previous, history, blocked, initialized) {
    const added = available.filter(n => !previous.includes(n) && !blocked.includes(n));
    if (initialized && previous.length > 0 && added.length > 0)
        return added[added.length - 1];
    if (available.includes(current) && (initialized || !blocked.includes(current)))
        return current;
    return fallback(available, history, blocked);
}

function mainOutput(current, available, blocked, musicSink) {
    if (available.includes(current))
        return current; // An explicitly selected device can remain blocked for future auto-switches.
    return fallback(available, [musicSink], blocked);
}

function pair(saved) {
    return {
        vsink: saved?.vsink ?? 0.4,
        vsinkMuted: saved?.vsinkMuted ?? false,
        phys: saved?.phys ?? 1.0,
        physMuted: saved?.physMuted ?? false
    };
}

function direct(saved) {
    return { vol: saved?.vol ?? 0.4, muted: saved?.muted ?? false };
}
