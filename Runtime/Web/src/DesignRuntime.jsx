import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Button } from '@astryxdesign/core/Button';
import { LiveControl, Positioned } from './Controls.jsx';
import { screenLayout } from './screenLayout.js';
import { blocked, emptyData, emptyResult, eventKey, formSubmission, listContent, listState, originalValue } from './designBehavior.js';

export function DesignRuntime({ design, data = emptyData, onAction = emptyResult, onSaveContact = emptyResult,
  connected = true, generated }) {
  const [route, setRoute] = useState(() => window.history.state?.designRoute ?? null);
  const [panel, setPanel] = useState(null);
  const [drafts, setDrafts] = useState({});
  const [errors, setErrors] = useState({});
  const [stored, setStored] = useState({});
  const dialog = useRef(null);
  const pages = new Map(design.pages.map(page => [page.id, page]));
  const lookup = new Map(design.pages.flatMap(page => page.layers.map(layer => [layer.id, layer])));

  const contact = route => design.contacts.find(contact => contact.id === route?.contact);
  function record(route) {
    if (route?.row) {
      const list = lookup.get(route.row.list);
      return list && listContent(list, design, data).rows.find(row => row.id === route.row.id);
    }
    const current = contact(route);
    if (!current) return;
    const { id, ...fields } = current;
    return { id, fields };
  }
  const valid = route => route?.entry === design.entry && pages.has(route.page) &&
    (!(route.contact || route.row) || record(route) != null);
  const visible = valid(route) ? route : { page: design.entry, entry: design.entry };
  const shownPanel = valid(panel) ? panel : null;
  const state = layer => data.controlStates?.[layer.id] ?? layer.behavior?.state ?? 'normal';
  function original(layer, route) {
    const legacy = contact(route);
    return originalValue(layer, data, record(route), layer.field
      ? legacy ? stored[legacy.id]?.[layer.field] ?? legacy[layer.field] : record(route)?.fields[layer.field]
      : undefined);
  }
  const signature = layer => JSON.stringify(layer.behavior?.binding ?? layer.field ?? null);
  const scalarKey = (layer, route) => JSON.stringify([route.page, route.contact ?? null, route.row ?? null, layer.id]);
  const errorKey = (layer, route) => JSON.stringify([scalarKey(layer, route), signature(layer), original(layer, route)]);

  useEffect(() => {
    function pop(event) { setRoute(event.state?.designRoute ?? null); }
    window.addEventListener('popstate', pop);
    return () => window.removeEventListener('popstate', pop);
  }, []);

  useEffect(() => {
    if (route && !valid(route)) {
      setRoute(null);
      window.history.replaceState(null, '');
    }
    if (panel && !valid(panel)) setPanel(null);
  }, [design, data, route, panel]);

  useEffect(() => {
    function retains(key, draft) {
      const [page, contact, row, id] = JSON.parse(key);
      const route = { page, contact, row, entry: design.entry };
      const layer = lookup.get(id);
      return layer && valid(route) && draft.signature === signature(layer) && draft.original === original(layer, route);
    }
    setDrafts(previous => Object.fromEntries(Object.entries(previous).filter(([key, draft]) => retains(key, draft))));
    setErrors(previous => Object.fromEntries(Object.entries(previous).filter(([key]) => {
      const [scalar, signature, original] = JSON.parse(key);
      return retains(scalar, { signature, original });
    })));
  }, [design, data, stored]);

  useLayoutEffect(() => {
    const element = dialog.current;
    if (!element) return;
    if (shownPanel && !element.open) element.showModal();
    else if (!shownPanel && element.open) element.close();
  }, [shownPanel]);

  function context(route, focus, inPanel) {
    const page = pages.get(route.page);
    function current(layer) {
      const base = original(layer, route);
      const draft = drafts[scalarKey(layer, route)];
      return draft?.original === base && draft.signature === signature(layer) ? draft.value : base;
    }
    const error = layer => errors[errorKey(layer, route)] ??
      (state(layer) === 'error' ? layer.behavior?.stateMessage ?? '请检查此字段' : undefined);
    const baseEvent = (name, layer, selected) => ({
      name, pageID: page.id, layerID: layer.id, values: {}, record: selected ?? record(route)
    });
    function edit(layer, value) {
      if (blocked(state(layer))) return;
      const key = scalarKey(layer, route);
      const draft = { original: original(layer, route), signature: signature(layer), value };
      setDrafts(previous => ({ ...previous, [key]: draft }));
      const action = layer.behavior?.changeAction;
      const result = action && onAction({ ...baseEvent(action, layer), values: { [eventKey(layer)]: value } });
      setErrors(previous => ({ ...previous, [errorKey(layer, route)]: result?.fieldErrors?.[eventKey(layer)] }));
    }
    function open(next) {
      if (!valid(next)) return;
      if (inPanel) setPanel(null);
      window.history.pushState({ designRoute: next }, '');
      setRoute(next);
    }
    function perform(action, layer, order, selected) {
      if (!action || blocked(state(layer))) return;
      switch (action.kind) {
        case 'navigate':
        case 'sheet': {
          const next = { page: action.target, entry: design.entry,
            contact: selected ? null : route.contact, row: selected ? { list: layer.id, id: selected.id } : route.row };
          if (!valid(next)) return;
          if (action.kind === 'sheet') setPanel(next);
          else open(next);
          break;
        }
        case 'back':
          if (inPanel) setPanel(null);
          else if (route.page !== design.entry || route.contact || route.row) window.history.back();
          break;
        case 'dismiss': setPanel(null); break;
        case 'named': if (action.name) onAction(baseEvent(action.name, layer, selected)); break;
        case 'submit': {
          if (!action.form || !action.name) return;
          const ordered = order.map(id => lookup.get(id));
          const submission = formSubmission(action.form, ordered, current, state);
          const failures = submission.errors;
          const event = { ...baseEvent(action.name, layer, selected), form: action.form, values: submission.values };
          if (!Object.keys(failures).length) {
            const result = onAction(event)?.fieldErrors;
            for (const field of submission.fields) {
              const message = result && Object.hasOwn(result, eventKey(field)) ? result[eventKey(field)] : undefined;
              if (message) failures[field.id] = message;
            }
          }
          setErrors(previous => ({
            ...previous, ...Object.fromEntries(submission.fields.map(field => [errorKey(field, route), failures[field.id]]))
          }));
          const invalid = submission.fields.filter(field => field.id in failures);
          focus((invalid.find(field => field.kind === 'input') ?? invalid[0])?.id);
          break;
        }
      }
    }
    return {
      display: layer => String(current(layer)), value: current, edit, error, state, perform,
      submit: (layer, order) => {
        const form = layer.behavior?.form;
        if (!form) return;
        const button = page.layers.find(candidate => candidate.behavior?.action?.kind === 'submit' &&
          candidate.behavior.action.form === form && !blocked(state(candidate)));
        if (button) perform(button.behavior.action, button, order);
      },
      list: layer => listContent(layer, design, data),
      rowTitle: layer => page.layers.find(child => child.parent === layer.id && child.kind === 'label')?.text,
      select: (layer, row, order) => {
        if (layer.behavior?.action) perform(layer.behavior.action, layer, order, row);
        else if (layer.destination && layer.behavior?.list) {
          perform({ kind: 'navigate', target: layer.destination }, layer, order, row);
        } else if (layer.destination) open({ page: layer.destination, contact: row.id, entry: design.entry });
      },
      save: () => {
        const legacy = contact(route);
        if (!legacy) return;
        const values = Object.fromEntries(page.layers.filter(layer => layer.kind === 'input' && layer.field)
          .map(layer => [layer.field, current(layer)]));
        setStored(previous => ({ ...previous, [legacy.id]: { ...previous[legacy.id], ...values } }));
        onSaveContact({ contactID: legacy.id, values });
      }
    };
  }

  const page = pages.get(visible.page);
  const title = contact(visible)?.name ?? page?.title;
  useEffect(() => { if (title) document.title = title; }, [title]);
  if (!page) return null;
  return <>
    <RuntimePage page={page} title={title} route={visible} generated={generated} makeContext={context}
      back={route && valid(route) ? () => window.history.back() : undefined} connected={connected} />
    <dialog ref={dialog} className="design-panel" aria-label={shownPanel ? pages.get(shownPanel.page).title : undefined}
      onCancel={event => { event.preventDefault(); setPanel(null); }}>
      {shownPanel && <RuntimePage page={pages.get(shownPanel.page)} title={pages.get(shownPanel.page).title} route={shownPanel}
        generated={generated} makeContext={context} close={() => setPanel(null)} connected />}
    </dialog>
  </>;
}

function RuntimePage({ page, title, route, generated, makeContext, back, close, connected }) {
  const heading = useRef(null);
  const viewport = useRef(null);
  const [size, setSize] = useState(null);
  const [focusField, focus] = useState(null);
  const previousRoute = useRef(null);
  const routeKey = JSON.stringify(route);
  const context = makeContext(route, id => focus(id ? { id } : null), !!close);
  const GeneratedControl = generated?.[page.id] ?? LiveControl;

  useLayoutEffect(() => {
    const element = viewport.current;
    function measure() {
      const { clientWidth: width, clientHeight: height } = element;
      const textScale = parseFloat(getComputedStyle(document.documentElement).fontSize) / 16;
      if (width) setSize(previous => previous?.width === width && previous.height === height && previous.textScale === textScale
        ? previous : { width, height, textScale });
    }
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [page.id, !!close]);

  useLayoutEffect(() => {
    if (previousRoute.current && previousRoute.current !== routeKey) heading.current.focus();
    previousRoute.current = routeKey;
  }, [routeKey]);

  useLayoutEffect(() => {
    if (!focusField) return;
    const target = heading.current.querySelector(`[data-layer="${CSS.escape(focusField.id)}"] input`);
    target?.focus();
  }, [focusField]);

  const availableWidth = size?.width ?? page.width;
  const textScale = size?.textScale ?? 1;
  const top = page.contentTop ?? 56;
  const layoutPage = { ...page, layers: page.layers.map(layer => {
    if (layer.kind === 'contactList') {
      const content = context.list(layer);
      if (listState(content) === 'ready') return {
        ...layer, contentMinimum: content.rows.length * (layer.behavior?.list?.rowHeight ?? 56) * Math.max(1, textScale)
      };
      if (listState(content) === 'empty' && layer.behavior?.list?.emptyAction) return { ...layer, contentMinimum: 88 };
    }
    if (layer.kind === 'input' && context.error(layer)) {
      const fieldHint = context.error(layer);
      const rows = Math.max(1, Math.ceil([...fieldHint].length * 12 * textScale / Math.max(1, Math.min(availableWidth, layer.width))));
      return { ...layer, fieldHint, contentMinimum: Math.max(44, Math.ceil(16 * 1.3 * textScale) + 16) + 4 + rows * 16 * textScale };
    }
    return layer;
  }) };
  const scene = screenLayout(layoutPage, availableWidth, (size?.height ?? page.height ?? 844) + top, top, textScale);
  context.order = scene.renderOrder;
  const lookup = new Map(page.layers.map(layer => [layer.id, layer]));
  function band(region, height) {
    return <div className={`page page-${region}`} style={{ height }}>
      {scene.renderOrder.map(id => {
        const layer = lookup.get(id);
        const frame = scene.items.get(id);
        const isActionRow = layer.kind === 'listRow' && layer.behavior?.action;
        if (frame.region !== region || scene.isContainer(layer) && !isActionRow) return null;
        return <Positioned key={id} layer={layer} frame={frame}>
          <GeneratedControl layer={layer} context={context} />
        </Positioned>;
      })}
    </div>;
  }
  const Surface = close ? 'section' : 'main';
  return <Surface className={route.contact ? 'artboard legacy-detail' : 'artboard'} ref={heading} tabIndex={-1} aria-label={title}
    style={{ maxWidth: page.adaptive ? Math.max(1440, page.width) : page.width }}>
    {(back || close) && <div className={back ? 'back' : 'panel-close'}>
      <Button label={back ? '返回' : '关闭'} size="lg" variant="secondary" onClick={back ?? close} autoFocus={!!close} />
    </div>}
    <div className="viewport" ref={viewport}>
      {scene.headerHeight > 0 && band('header', scene.headerHeight)}
      <div className="scroll-body" key={routeKey} tabIndex={0} aria-label="页面内容">{band('body', scene.bodyHeight)}</div>
      {scene.footerHeight > 0 && band('footer', scene.footerHeight)}
    </div>
    {!connected && <p role="status" className="connection">预览连接已断开</p>}
  </Surface>;
}
