// SPDX-License-Identifier: MPL-2.0
// Keep the flag in the renderer. A SPA can replace a field after the user has
// typed into it; reading only the current DOM would lose that draft.
static constexpr char kObserveEdits[] = R"JS((() => {
  let edited = false;
  const mark = () => { edited = true; };
  for (const event of ['beforeinput', 'input', 'change', 'compositionstart'])
    window.addEventListener(event, mark, {capture:true, passive:true, once:true});
  return (forSleep) => {
    // A newly created WebContents has a new sessionStorage namespace. Keep
    // session-only state and reading positions that a URL reload cannot restore.
    if (forSleep && (window.scrollX || window.scrollY || sessionStorage.length ||
        (history.length <= 1 && history.state !== null))) return false;
    if (edited || document.designMode === 'on' || document.pictureInPictureElement ||
        navigator.mediaSession?.playbackState === 'playing') return false;
    const roots = [document];
    let work = 0;
    while (roots.length) {
      const nodes = document.createTreeWalker(roots.pop(), NodeFilter.SHOW_ELEMENT);
      while (nodes.nextNode()) {
        if (++work > 45000) return false;
        const el = nodes.currentNode;
        if (el.shadowRoot) roots.push(el.shadowRoot);
        switch (el.localName) {
          case 'audio': case 'video':
            if (!el.paused && !el.ended) return false;
            break;
          case 'input':
            if (el.type === 'hidden' || el.type === 'button' || el.type === 'submit') break;
            if (el.type === 'radio' || el.type === 'checkbox') {
              if (el.checked !== el.defaultChecked) return false;
            } else if (el.value !== el.defaultValue) {
              if (el.type !== 'range' && el.type !== 'color') return false;
              // Chromium normalizes empty defaults (a range starts at its
              // midpoint). Reconstruct only the standard control, off-document.
              const pristine = document.createElement('input');
              pristine.type = el.type;
              for (const key of ['min','max','step','alpha','colorspace']) {
                if (el.hasAttribute(key)) pristine.setAttribute(key,el.getAttribute(key));
              }
              pristine.defaultValue = el.defaultValue;
              if (el.value !== pristine.value) return false;
            }
            break;
          case 'textarea':
            if (el.value !== el.defaultValue) return false;
            break;
          case 'select':
            if (el.options.length > 1000) return false;
            {
              let first = -1, lastDefault = -1;
              for (const option of el.options) {
                if (el.multiple && option.selected !== option.defaultSelected) return false;
                if (option.defaultSelected) lastDefault = option.index;
                if (first < 0 && !option.matches(':disabled')) first = option.index;
              }
              if (!el.multiple && el.selectedIndex !== (lastDefault >= 0 || el.size > 1 ? lastDefault : first)) return false;
            }
            break;
        }
      }
    }
    return true;
  };
})())JS";
