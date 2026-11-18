// Mirrors ScreenLayout.swift. Both runtimes and the editor resolve the same authored geometry.
export function screenLayout(page, width, height, top, textScale = 1) {
  const device = width < 600 ? 'phone' : width < 1000 ? 'tablet' : 'desktop';
  const hierarchy = new Map();
  const items = new Map();
  const renderOrder = [];
  let availableHeight = Math.max(0, height - top);

  for (const layer of page.layers) {
    const parent = layer.parent ?? null;
    if (!hierarchy.has(parent)) hierarchy.set(parent, []);
    hierarchy.get(parent).push(layer);
  }

  const geometry = layer => ({ ...layer.geometry, ...layer.overrides?.[device] });
  const raw = layer => geometry(layer).frame ?? layer;
  const isContainer = layer => ['layout', 'labeledInput', 'listRow', 'actionBar'].includes(layer.kind);
  const minWidth = layer => ({ contactList: 120, setting: 116, toggle: 52, divider: 4 })[layer.kind] ?? 44;
  const isActionRow = layer => layer.kind === 'listRow' && layer.behavior?.action;
  const minHeight = layer => isActionRow(layer) ? 44 : isContainer(layer) ? 4 :
    ({ title: 24, label: 24, divider: 1, contactList: 56 })[layer.kind] ?? 44;
  const font = layer => layer.kind === 'title' && layer.field !== 'phone' ? 28 : 16;
  const textPadding = layer => ['button', 'input'].includes(layer.kind) ? 24 : 0;
  const lineWidths = (text, size) => text.split('\n').map(line =>
    Array.from(line).reduce((sum, char) => sum + (char.codePointAt(0) < 128 ? 0.56 : 1), 0) * size * textScale);
  const lineCount = (text, size, width) => lineWidths(text, size)
    .reduce((sum, w) => sum + Math.max(1, Math.ceil(w / Math.max(1, width))), 0);

  function intrinsicWidth(layer) {
    const frame = raw(layer);
    const children = hierarchy.get(layer.id) ?? [];
    if (isContainer(layer) && children.length) {
      const spec = geometry(layer);
      const gap = spec.gap ?? 12;
      const widths = children.map(child => geometry(child).width === 'content' ? intrinsicWidth(child) : raw(child).width);
      const widest = Math.max(...widths);
      const columns = Math.min(widths.length, spec.columns ?? 2);
      switch (spec.arrangement) {
        case 'vertical': return widest;
        case 'horizontal': return widths.reduce((a, b) => a + b, 0) + (widths.length - 1) * gap;
        case 'grid': return widest * columns + (columns - 1) * gap;
        default: return Math.max(...children.map((child, index) => raw(child).x + widths[index]));
      }
    }
    if (['title', 'label', 'button', 'input'].includes(layer.kind)) {
      return Math.max(0, ...lineWidths(layer.text, font(layer))) + textPadding(layer);
    }
    return frame.width;
  }

  function extent(layer, available, proportional = 1) {
    const frame = raw(layer);
    const mode = geometry(layer).width;
    let length = frame.width * proportional;
    if (mode === 'fixed') length = frame.width;
    if (mode === 'fill') length = available;
    if (mode === 'content') length = intrinsicWidth(layer);
    return Math.min(Math.max(0, available), Math.max(minWidth(layer), length));
  }

  function intrinsicHeight(layer, width) {
    if (!['title', 'label', 'button', 'input'].includes(layer.kind)) return layer.styleHeight ?? raw(layer).height;
    const lines = layer.kind === 'input' ? 1 : lineCount(layer.text, font(layer), width - textPadding(layer));
    const padding = ['input', 'button'].includes(layer.kind) ? 16 : 4;
    const field = Math.max(minHeight(layer), Math.ceil(lines * font(layer) * 1.3 * textScale) + padding);
    return layer.fieldHint ? field + 4 + Math.ceil(lineCount(layer.fieldHint, 12, width) * 16 * textScale) : field;
  }

  function rowWidths(row, arrangement, count, width, cell) {
    if (arrangement === 'grid' || count === 1) return row.map(child => extent(child, cell));
    const fixed = row.map(child => geometry(child).width === 'fill' ? 0 : extent(child, width));
    const used = fixed.reduce((sum, w) => sum + w, 0);
    const fills = fixed.filter(w => w === 0).length;
    const minimum = row.reduce((sum, child, index) => sum + (fixed[index] === 0 ? minWidth(child) : 0), 0);
    const fixedSpace = Math.max(0, width - Math.min(minimum, width / 2));
    const scale = used > fixedSpace && used > 0 ? fixedSpace / used : 1;
    const fill = Math.max(0, width - used * scale) / Math.max(1, fills);
    return fixed.map(w => w > 0 ? w * scale : fill);
  }

  function measure(layer, width, room) {
    const spec = geometry(layer);
    const frame = raw(layer);
    const proposed = spec.height === 'fill' ? Math.max(minHeight(layer), room)
      : spec.height === 'fixed' ? frame.height : layer.styleHeight ?? frame.height;
    let children = hierarchy.get(layer.id) ?? [];
    if (spec.order) {
      const ranks = new Map(spec.order.map((id, index) => [id, index]));
      children = [...children].sort((a, b) => (ranks.get(a.id) ?? ranks.size) - (ranks.get(b.id) ?? ranks.size));
    }
    if (!children.length) {
      return { id: layer.id, width, height: Math.max(layer.contentMinimum ?? 0, spec.height === 'content' ? intrinsicHeight(layer, width) : proposed), children: [] };
    }

    const arrangement = spec.arrangement ?? 'free';
    const narrow = spec.stackAtNarrowWidth && width < 420;
    const columns = narrow ? 1 : arrangement === 'horizontal' ? children.length
      : arrangement === 'grid' ? Math.min(children.length, spec.columns ?? 2) : 1;
    const gap = columns > 1 ? Math.min(spec.gap ?? 12, Math.max(0, (width - 16 * columns) / (columns - 1))) : spec.gap ?? 12;
    const plans = [];
    let bottom = 0;

    if (arrangement === 'free') {
      for (const child of children) {
        const frame = raw(child);
        const x = Math.min(frame.x, Math.max(0, width - minWidth(child)));
        const plan = measure(child, extent(child, Math.max(0, width - x)), Math.max(0, proposed - frame.y));
        plans.push({ x, y: frame.y, plan });
        bottom = Math.max(bottom, frame.y + plan.height);
      }
    } else {
      const rowCount = Math.ceil(children.length / columns);
      const rowHeight = Math.max(0, (proposed - gap * (rowCount - 1)) / rowCount);
      for (let start = 0; start < children.length; start += columns) {
        const row = children.slice(start, start + columns);
        const count = arrangement === 'grid' ? columns : row.length;
        const available = Math.max(0, width - gap * (count - 1));
        const cell = available / count;
        const widths = rowWidths(row, arrangement, count, available, cell);
        let x = 0;
        let maxHeight = 0;
        row.forEach((child, index) => {
          const w = widths[index];
          const plan = measure(child, w, spec.height === 'content' ? raw(child).height : rowHeight);
          plans.push({ x, y: bottom, plan });
          x += (arrangement === 'grid' ? cell : w) + gap;
          maxHeight = Math.max(maxHeight, plan.height);
        });
        bottom += maxHeight + gap;
      }
      bottom -= gap;
    }
    const measured = Math.max(minHeight(layer), spec.height === 'content' ? bottom : Math.max(proposed, bottom));
    if (isActionRow(layer) && arrangement === 'horizontal' && !narrow) {
      for (const child of plans) child.y = Math.max(0, (measured - child.plan.height) / 2);
    }
    return { id: layer.id, width, height: measured, children: plans };
  }

  function place(plan, x, y, region) {
    items.set(plan.id, { x, y, width: plan.width, height: plan.height, region });
    renderOrder.push(plan.id);
    for (const child of plan.children) place(child.plan, x + child.x, y + child.y, region);
  }

  function placeRoots(region) {
    let end = 0;
    const ratio = width / Math.max(1, page.width);
    for (const layer of hierarchy.get(null) ?? []) {
      const spec = geometry(layer);
      if ((spec.region ?? 'body') !== region) continue;
      const frame = raw(layer);
      const minimum = Math.min(width, minWidth(layer));
      const x = Math.min(Math.max(0, spec.width ? frame.x : frame.x * ratio), Math.max(0, width - minimum));
      const y = region === 'body' ? Math.max(0, frame.y - top) : end;
      const available = Math.max(0, width - x - (spec.width === 'fill' ? Math.min(24, x) : 0));
      const w = Math.max(minimum, extent(layer, available, ratio));
      const plan = measure(layer, w, Math.max(0, availableHeight - y));
      place(plan, x, y, region);
      end = Math.max(end, y + plan.height);
    }
    return end;
  }

  const headerHeight = placeRoots('header');
  const footerHeight = placeRoots('footer');
  availableHeight = Math.max(0, availableHeight - headerHeight - footerHeight);
  const bodyHeight = Math.max(availableHeight, placeRoots('body') + 24);
  return { items, renderOrder, headerHeight, footerHeight, bodyHeight, isContainer };
}
