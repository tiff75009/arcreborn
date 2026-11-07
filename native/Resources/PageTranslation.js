// Executed only on demand in a Chromium isolated world. The live DOM, forms,
// events and browsing history stay in place. A new document has its own state.
(mode, token, output) => {
    const key = "__arcPageTranslation";
    const state = globalThis[key];
    const excluded = 'script,style,noscript,template,textarea,input,select,code,pre,kbd,samp,svg,math,canvas,[hidden],[inert],[aria-hidden="true"],[translate="no" i],.notranslate';
    if (mode === "collect") {
        const entries = [], strings = [], index = new Map();
        let size = 0;
        const scan = root => {
            const doc = root.ownerDocument || root;
            const walker = doc.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
                acceptNode(node) {
                    if (node.nodeType !== 1) return NodeFilter.FILTER_ACCEPT;
                    if (node.matches(excluded) || node.isContentEditable) return NodeFilter.FILTER_REJECT;
                    const style = doc.defaultView.getComputedStyle(node);
                    if (style.display === "none" || style.visibility === "hidden") return NodeFilter.FILTER_REJECT;
                    return NodeFilter.FILTER_ACCEPT;
                }
            });
            let node;
            while ((node = walker.nextNode())) {
                if (node.nodeType === 1) {
                    if (node.shadowRoot) scan(node.shadowRoot);
                    if (node.localName === "iframe" && node.contentDocument?.body) scan(node.contentDocument.body);
                    continue;
                }
                const raw = node.data, text = raw.trim();
                if (!text || !/\p{L}/u.test(text)) continue;
                if (!index.has(text)) {
                    size += text.length;
                    if (size > 800000 || strings.length >= 16000) throw Error("limit");
                    index.set(text, strings.length); strings.push(text);
                }
                entries.push({node, raw, i: index.get(text)});
                if (entries.length > 40000) throw Error("limit");
            }
        };
        try { if (document.body && !document.body.isContentEditable && !document.body.closest(excluded)) scan(document.body); }
        catch (e) { return {error: e.message === "limit" ? "limit" : "unavailable"}; }
        if (!strings.length) return {error:"empty"};
        globalThis[key] = {token, strings, entries};
        return {strings, lang:document.documentElement.lang || ""};
    }
    if (!state || state.token !== token) return false;
    if (mode === "apply") {
        if (!Array.isArray(output) || output.length !== state.strings.length || !output.every(s => typeof s === "string" && s.trim())) return false;
        let changed = 0;
        for (const e of state.entries) {
            if (!e.node.isConnected || e.node.data !== e.raw || e.node.parentElement?.isContentEditable || e.node.parentElement?.closest(excluded)) continue;
            const start = e.raw.indexOf(state.strings[e.i]);
            e.translated = e.raw.slice(0,start) + output[e.i] + e.raw.slice(start + state.strings[e.i].length);
            e.node.data = e.translated; changed++;
        }
        state.strings = null;
        return changed > 0;
    }
    if (mode === "restore") {
        for (const e of state.entries) {
            if (e.translated != null && e.node.isConnected && e.node.data === e.translated) e.node.data = e.raw;
        }
    }
    delete globalThis[key];
    return true;
}
