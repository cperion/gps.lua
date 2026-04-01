# Interactive UI demo

Run from the repository root with:

```bash
love examples/ui
```

This demo shows a fuller `mgps` stack:

- `UI -> View -> LovePaint`
- `UI -> View -> Hit`
- `Clip` and `Transform`
- separate paint and hit-testing pipelines
- payload-only vs state-shaping updates
- hover, click, and drag interaction

## Controls

- `1`, `2`, `3` switch between short / medium / long text
- hover the buttons, viewport text, and slider to exercise hit testing
- drag the slider to scroll the clipped text horizontally
- `Esc` quits

## What to notice

- Switching between **short** and **medium** may keep the same text capacity bucket, so only payload changes.
- Switching to **long** forces a larger `TextBlob` resource, so the text terminal changes **state shape**.
- Dragging the slider only changes transform payload, not the terminal code shape.
- Paint and hit testing are compiled from the same authored source tree but into separate terminals.
