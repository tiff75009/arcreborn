// Runs on demand in the document's isolated world. Each distinct string owns
// its original text nodes so individual results can be applied in any order.
(mode, token, updates) => {
    const key = "__arcPageTranslation";
    const state = globalThis[key];
    const excluded = 'script,style,noscript,template,textarea,input,select,code,pre,kbd,samp,svg,math,canvas,[hidden],[inert],[aria-hidden="true"],[translate="no" i],.notranslate';
    if (mode === "collect") {
        const groups = new Map(), visible = new WeakMap();
        let size = 0, count = 0;
        const scan = (root, frameVisible) => {
            const doc = root.ownerDocument || root;
            const win = doc.defaultView;
            const inViewport = el => {
                if (!frameVisible) return false;
                if (!visible.has(el)) {
                    const r = el.getBoundingClientRect();
                    visible.set(el, r.height > 0 && r.width > 0 && r.top < win.innerHeight && r.bottom > 0 &&
                        r.left < win.innerWidth && r.right > 0);
                }
                return visible.get(el);
            };
            const walker = doc.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
                acceptNode(node) {
                    if (node.nodeType !== 1) return NodeFilter.FILTER_ACCEPT;
                    if (node.matches(excluded) || node.isContentEditable) return NodeFilter.FILTER_REJECT;
                    const style = win.getComputedStyle(node);
                    return style.display === "none" || style.visibility === "hidden" ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
                }
            });
            let node;
            while ((node = walker.nextNode())) {
                if (node.nodeType === 1) {
                    if (node.shadowRoot) scan(node.shadowRoot, inViewport(node));
                    if (node.localName === "iframe" && node.contentDocument?.body) scan(node.contentDocument.body, inViewport(node));
                    continue;
                }
                const raw = node.data, text = raw.trim();
                if (!text || !/\p{L}/u.test(text)) continue;
                if (!groups.has(text)) {
                    size += text.length;
                    if (size > 800000 || groups.size >= 16000) throw Error("limit");
                    groups.set(text, {text, visible:false, entries:[]});
                }
                const group = groups.get(text);
                const parent = node.parentElement || root.host;
                if (parent && !group.visible) group.visible = inViewport(parent);
                group.entries.push({node, raw});
                if (++count > 40000) throw Error("limit");
            }
        };
        try { if (document.body && !document.body.isContentEditable && !document.body.closest(excluded)) scan(document.body, true); }
        catch (e) { return {error:e.message === "limit" ? "limit" : "unavailable"}; }
        if (!groups.size) return {error:"empty"};
        const ordered = Array.from(groups.values()).sort((a,b) => Number(b.visible) - Number(a.visible));
        globalThis[key] = {token, groups:ordered};
        return {strings:ordered.map(g => g.text),lang:document.documentElement.lang || ""};
    }
    if (!state || state.token !== token) return false;
    if (mode === "apply") {
        for (const [index, translated] of updates) {
            const group = state.groups[index];
            if (!group || typeof translated !== "string" || !translated.trim()) return false;
            for (const e of group.entries) {
                if (!e.node.isConnected || e.node.data !== e.raw || e.node.parentElement?.isContentEditable || e.node.parentElement?.closest(excluded)) continue;
                const start = e.raw.indexOf(group.text);
                e.translated = e.raw.slice(0,start) + translated + e.raw.slice(start + group.text.length);
                e.node.data = e.translated;
            }
        }
        return true;
    }
    if (mode !== "restore") return false;
    for (const group of state.groups) {
        for (const e of group.entries) {
            if (e.translated !== undefined && e.node.isConnected && e.node.data === e.translated) e.node.data = e.raw;
        }
    }
    delete globalThis[key];
    return true;
}
