import React from 'react';
import { Button } from '@astryxdesign/core/Button';
import { Item } from '@astryxdesign/core/Item';
import { TextInput } from '@astryxdesign/core/TextInput';
import { blocked, listState } from './designBehavior.js';

export function Title({ layer, context }) {
  const text = context.display(layer);
  return layer.field === 'phone' ? <p className="phone-number">{text}</p> : <h1>{text}</h1>;
}

export function Field({ layer, context }) {
  const error = context.error(layer);
  const message = error ?? layer.fieldHint;
  const hint = React.useId();
  const inlineLabel = layer.field || layer.behavior?.binding && !layer.inputLabel;
  return <div className="design-field">
    <div className="field-control">
      {inlineLabel && <span aria-hidden="true">{layer.text}</span>}
      <TextInput label={layer.inputLabel || layer.text || '输入框'} isLabelHidden placeholder={inlineLabel ? undefined : layer.text}
        type={layer.inputType ?? 'text'} value={String(context.value(layer))} onChange={value => context.edit(layer, value)}
        aria-invalid={!!error} aria-describedby={message ? hint : undefined} onEnter={() => context.submit(layer, context.order)} isDisabled={blocked(context.state(layer))} width="full" size="lg"
        className="design-input" />
    </div>
    {message && <span className={error ? 'field-hint field-error' : 'field-hint'} id={hint} role={error ? 'alert' : undefined}>{message}</span>}
  </div>;
}

export function Action({ layer, context, onClick }) {
  const secondary = layer.secondaryButton === true;
  const state = context.state(layer);
  const action = layer.behavior?.action;
  const message = state === 'busy' || state === 'error' ? layer.behavior?.stateMessage : undefined;
  const status = state === 'error' ? message || "操作失败" : undefined;
  return <Button label={message || layer.text} aria-label={status ? `${layer.text}，${status}` : undefined} size="lg" variant={secondary ? 'secondary' : 'primary'}
    className={secondary ? 'design-action design-action-secondary' : 'design-action'}
    isLoading={state === 'busy'} data-state={state} isDisabled={state === 'disabled'}
    width="full" style={{ borderRadius: layer.cornerRadius ?? 8 }}
    onClick={action ? () => context.perform(action, layer, context.order) : onClick} />;
}

export function ListRow({ layer, context }) {
  return layer.behavior?.action && <button type="button" className="row-hit" aria-label={context.rowTitle(layer) ?? '列表行'}
    disabled={blocked(context.state(layer))} onClick={() => context.perform(layer.behavior.action, layer, context.order)} />;
}

export function ContactList({ layer, context }) {
  const list = layer.behavior?.list;
  const content = context.list(layer);
  const state = listState(content);
  if (state !== 'ready') {
    const messages = { empty: list?.emptyText ?? '暂无联系人', loading: list?.loadingText ?? '正在加载',
      failed: list?.failureText ?? '无法加载联系人' };
    return <div className={`list-state list-${state}`}>
      <p role={state === 'failed' ? 'alert' : 'status'}>{content.message ?? messages[state]}</p>
      {state === 'empty' && list?.emptyButton && list.emptyAction && <Button label={list.emptyButton} size="lg"
        variant="secondary" onClick={() => context.perform(list.emptyAction, layer, context.order)} />}
    </div>;
  }
  const connected = layer.behavior?.action || layer.destination;
  return <ul className="contacts" aria-label={layer.text || '联系人'}>
    {content.rows.map(record => <li key={record.id} style={{ '--row-height': `max(${list?.rowHeight ?? 56}px, ${(list?.rowHeight ?? 56) / 16}rem)` }}>
      <Item label={String(record.fields[list?.titleKey ?? 'name'] ?? '')}
        description={String(record.fields[list?.detailKey ?? 'phone'] ?? '')}
        onClick={connected && !blocked(context.state(layer)) ? () => context.select(layer, record, context.order) : undefined}
        endContent={connected ? <span className="chevron" aria-hidden="true" /> : undefined} />
    </li>)}
  </ul>;
}

export function Setting({ layer, context }) {
  return <label className="setting-control">{layer.text}
    <input type="checkbox" aria-label={layer.text} checked={context.value(layer) === true}
      disabled={blocked(context.state(layer))} onChange={event => context.edit(layer, event.target.checked)} />
  </label>;
}

export function DesignLabel({ layer, context }) {
  return <span className="design-label">{context.display(layer)}</span>;
}

export function DesignToggle({ layer, context }) {
  return <label className="design-toggle-control">
    <input type="checkbox" aria-label={layer.text || layer.behavior?.binding?.key || '开关'} checked={context.value(layer) === true}
      disabled={blocked(context.state(layer))} onChange={event => context.edit(layer, event.target.checked)} />
  </label>;
}

export function DesignDivider() {
  return <hr className="design-divider" />;
}

export function DesignImage({ layer }) {
  return layer.image ? <img className="design-image" src={`data:image/png;base64,${layer.image}`} alt={layer.text} /> : null;
}

export function Positioned({ layer, frame, children }) {
  return <div className={'layer ' + layer.kind} data-layer={layer.id} style={{
    insetInlineStart: frame.x, width: frame.width, top: frame.y, height: frame.height
  }}>{children}</div>;
}

export function LiveControl({ layer, context }) {
  switch (layer.kind) {
    case 'title': return <Title layer={layer} context={context} />;
    case 'input': return <Field layer={layer} context={context} />;
    case 'button': return <Action layer={layer} context={context} onClick={layer.savesContact ? context.save : undefined} />;
    case 'contactList': return <ContactList layer={layer} context={context} />;
    case 'listRow': return <ListRow layer={layer} context={context} />;
    case 'setting': return <Setting layer={layer} context={context} />;
    case 'label': return <DesignLabel layer={layer} context={context} />;
    case 'toggle': return <DesignToggle layer={layer} context={context} />;
    case 'divider': return <DesignDivider />;
    case 'image': return <DesignImage layer={layer} />;
    default: return null;
  }
}
