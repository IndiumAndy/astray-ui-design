export const emptyData = Object.freeze({});
export const emptyResult = () => ({});
export const blocked = state => state === 'disabled' || state === 'busy';

export function listContent(layer, design, data) {
  const list = layer.behavior?.list;
  return list ? data.lists?.[list.key] ?? list.sample : {
    state: 'ready', rows: design.contacts.map(({ id, ...fields }) => ({ id, fields }))
  };
}

export function listState(content) {
  return content.state === 'ready' && !content.rows.length ? 'empty' : content.state;
}

export function originalValue(layer, data, record, legacy) {
  const binding = layer.behavior?.binding;
  if (binding) {
    const source = binding.source === 'record' ? record?.fields : data.values;
    const value = source && Object.hasOwn(source, binding.key) ? source[binding.key] : binding.sample;
    if (value != null) return value;
  }
  if (legacy != null) return legacy;
  if (['toggle', 'setting'].includes(layer.kind)) return layer.isOn;
  return layer.kind === 'input' ? '' : layer.text;
}

export const eventKey = layer => layer.behavior?.submissionKey ?? layer.behavior?.binding?.key ?? layer.field ?? layer.id;

const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

export function fieldError(rules, value) {
  if (!rules) return undefined;
  const text = String(value);
  const trimmed = text.trim();
  if (!trimmed) return rules.required ? rules.message ?? '请填写此字段' : undefined;
  const count = [...segmenter.segment(text)].length;
  if (rules.minimum != null && count < rules.minimum) return rules.message ?? `至少输入 ${rules.minimum} 个字符`;
  if (rules.maximum != null && count > rules.maximum) return rules.message ?? `最多输入 ${rules.maximum} 个字符`;
  if (rules.email && !/^[^\s@]+@[^\s@.]+(?:\.[^\s@.]+)+$/.test(trimmed)) {
    return rules.message ?? '请输入有效的邮箱地址';
  }
}

export function formSubmission(form, layers, current, state) {
  const fields = layers.filter(layer => ['input', 'toggle', 'setting'].includes(layer.kind)
    && layer.behavior?.form === form && !blocked(state(layer)));
  const values = new Map();
  const errors = {};
  for (const field of fields) {
    const value = current(field);
    const key = eventKey(field);
    const error = values.has(key) ? '表单内的提交键重复' : fieldError(field.behavior?.rules, value);
    values.set(key, value);
    if (error) errors[field.id] = error;
  }
  return { fields, values: Object.fromEntries(values), errors };
}
