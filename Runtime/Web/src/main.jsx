import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { DesignRuntime } from './DesignRuntime.jsx';
import { generatedPages } from './GeneratedPages.jsx';
import { onAction, onSaveContact } from './contactActions.js';
import builtDesign from './Design.json';
import '@astryxdesign/core/reset.css';
import '@astryxdesign/core/astryx.css';
import '@astryxdesign/theme-neutral/theme.css';
import './screen.css';

const live = builtDesign === null;

function useDesign() {
  const [design, setDesign] = useState(builtDesign);
  const [connected, setConnected] = useState(true);
  useEffect(() => {
    if (!live) return;
    const abort = new AbortController();
    let next;
    let previous;
    async function refresh() {
      try {
        const response = await fetch('./design.json', { cache: 'no-store', signal: abort.signal });
        if (!response.ok) throw new Error('Preview unavailable');
        const json = await response.text();
        if (previous !== json) {
          setDesign(JSON.parse(json));
          previous = json;
        }
        setConnected(true);
      } catch {
        if (!abort.signal.aborted) setConnected(false);
      }
      if (!abort.signal.aborted) next = setTimeout(refresh, 200);
    }
    refresh();
    return () => { abort.abort(); clearTimeout(next); };
  }, []);
  return { design, connected };
}

function App() {
  const { design, connected } = useDesign();
  if (!design) return <p role="status" className="connection">{connected ? '正在打开预览' : '请在编辑器中重新运行预览'}</p>;
  return <DesignRuntime design={design} connected={connected} generated={live ? undefined : generatedPages}
    onAction={onAction} onSaveContact={onSaveContact} />;
}

createRoot(document.getElementById('root')).render(<App />);
