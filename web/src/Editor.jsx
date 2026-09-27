import { useEffect, useMemo, useRef, useState } from 'react';
import { fetchNui, isEditorPreview, mockEditor } from './nui';

const r2 = (n) => Math.round(n * 100) / 100;
const wrap360 = (n) => r2(((n % 360) + 360) % 360);
const clone = (o) => JSON.parse(JSON.stringify(o));
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 30) || 'scene';

function animKind(a) {
    if (!a) return 'none';
    if (a.preset) return 'preset';
    if (a.scenario !== undefined) return 'scenario';
    return 'anim';
}

// Text while typing, number on commit: rounding every keystroke ate "." and "-"
function Num({ label, value, onChange, step }) {
    const [text, setText] = useState(null);
    const cancel = useRef(false);
    const commit = () => {
        const n = Number(String(text).replace(',', '.'));
        if (!cancel.current && text !== null && String(text).trim() !== '' && Number.isFinite(n)) onChange(n);
        cancel.current = false;
        setText(null);
    };
    return (
        <label className="ed-num">
            <span>{label}</span>
            <button tabIndex={-1} onClick={() => onChange(value - step)}>−</button>
            <input
                type="text" inputMode="decimal"
                value={text ?? String(value)}
                onFocus={(e) => { setText(String(value)); e.target.select(); }}
                onChange={(e) => setText(e.target.value)}
                onBlur={commit}
                onKeyDown={(e) => {
                    if (e.key === 'Enter') e.currentTarget.blur();
                    else if (e.key === 'Escape') { cancel.current = true; e.currentTarget.blur(); }
                    else if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
                        e.preventDefault();
                        const base = Number(String(text).replace(',', '.'));
                        const next = Math.round(((Number.isFinite(base) ? base : value) + (e.key === 'ArrowUp' ? step : -step)) * 100) / 100;
                        onChange(next);
                        setText(String(next));
                    }
                }}
            />
            <button tabIndex={-1} onClick={() => onChange(value + step)}>+</button>
        </label>
    );
}

function AnimEditor({ anim, animations, onChange, onReplay }) {
    const kind = animKind(anim);
    const setKind = (k) => {
        if (k === 'none') onChange(null);
        else if (k === 'preset') onChange({ preset: animations[0]?.id });
        else if (k === 'scenario') onChange({ scenario: 'WORLD_HUMAN_STAND_IMPATIENT' });
        else onChange({ dict: '', clip: '', flag: 1 });
    };

    return (
        <div className="ed-anim">
            <div className="ed-seg">
                {['preset', 'anim', 'scenario', 'none'].map((k) => (
                    <button key={k} className={kind === k ? 'on' : ''} onClick={() => setKind(k)}>
                        {k === 'anim' ? 'Dict / Clip' : k[0].toUpperCase() + k.slice(1)}
                    </button>
                ))}
            </div>

            {kind === 'preset' && (
                <select value={anim.preset} onChange={(e) => onChange({ preset: e.target.value })}>
                    {animations.map((a) => (
                        <option key={a.id} value={a.id}>{a.label}{a.kind === 'scenario' ? ' (scenario)' : ''}</option>
                    ))}
                </select>
            )}
            {kind === 'anim' && (
                <>
                    <input placeholder="anim dict" value={anim.dict} onChange={(e) => onChange({ ...anim, dict: e.target.value.trim() })} />
                    <div className="ed-row">
                        <input placeholder="clip" value={anim.clip} onChange={(e) => onChange({ ...anim, clip: e.target.value.trim() })} />
                        <input className="flag" type="number" title="Anim flag (1 = loop, 49 = loop upper body)" value={anim.flag}
                            onChange={(e) => onChange({ ...anim, flag: Number(e.target.value) || 0 })} />
                    </div>
                </>
            )}
            {kind === 'scenario' && (
                <input placeholder="WORLD_HUMAN_..." value={anim.scenario} onChange={(e) => onChange({ scenario: e.target.value.trim().toUpperCase() })} />
            )}
            {kind !== 'none' && <button className="ed-btn" onClick={onReplay}><i className="fa-solid fa-rotate-right" /> Replay</button>}
        </div>
    );
}

export default function Editor() {
    const [open, setOpen] = useState(false);
    const [scenes, setScenes] = useState([]);
    const [saved, setSaved] = useState('');
    const [active, setActive] = useState(null);
    const [sceneId, setSceneId] = useState(null);
    const [slotIdx, setSlotIdx] = useState(0);
    const [animations, setAnimations] = useState([]);
    const [weathers, setWeathers] = useState([]);
    const [mode, setMode] = useState('panel'); // panel | walk | freecam
    const [preview, setPreview] = useState(false);
    const [positions, setPositions] = useState([]);
    const [step, setStep] = useState(0.05);
    const [hStep, setHStep] = useState(5);
    const [keyTarget, setKeyTarget] = useState('ped'); // ped | slotcam | scenecam
    const [confirmReset, setConfirmReset] = useState(false);
    const [playing, setPlaying] = useState(false);
    const sceneIdRef = useRef(null);
    sceneIdRef.current = sceneId;

    const scene = scenes.find((s) => s.id === sceneId) || null;
    const slot = scene?.slots[slotIdx] || null;
    const dirty = useMemo(() => JSON.stringify({ scenes, active }) !== saved, [scenes, active, saved]);

    const updateScene = (fn) => setScenes((list) => list.map((s) => (s.id === sceneId ? fn(clone(s)) : s)));
    const updateSlot = (fn) => updateScene((s) => { fn(s.slots[slotIdx]); return s; });

    // Push the draft to Lua so preview peds follow every change
    useEffect(() => {
        if (!open) return;
        const t = setTimeout(() => fetchNui('editor:draft', { scene, selected: slot ? slotIdx + 1 : null }), 60);
        return () => clearTimeout(t);
    }, [open, scene, slotIdx]);

    useEffect(() => {
        const load = (list, act, resetSelection) => {
            setScenes(clone(list));
            setActive(act);
            setSaved(JSON.stringify({ scenes: list, active: act }));
            if (resetSelection || !list.some((s) => s.id === sceneIdRef.current)) {
                setSceneId(act || list[0]?.id || null);
                setSlotIdx(0);
            }
        };
        const onMessage = ({ data }) => {
            switch (data.action) {
                case 'openEditor':
                    setAnimations(data.animations || []);
                    setWeathers(data.weathers || []);
                    load(data.scenes || [], data.active, true);
                    setMode('panel');
                    setPreview(false);
                    setOpen(true);
                    break;
                case 'editorSync': load(data.scenes || [], data.active, false); break;
                case 'closeEditor': setOpen(false); break;
                case 'editorFocus': setMode('panel'); break;
                case 'editorPreview': setPreview(!!data.active); break;
                case 'editorPositions': setPositions(data.items || []); break;
                case 'editorFreecam':
                    if (data.active) { setMode('freecam'); break; }
                    setMode('panel');
                    if (data.camera) {
                        const c = data.camera;
                        freecamResultRef.current(data.target, { x: r2(c.x), y: r2(c.y), z: r2(c.z), rx: r2(c.rx), ry: 0, rz: r2(c.rz), fov: r2(c.fov) });
                    }
                    break;
                case 'editorPlaying': setPlaying(!!data.active); break;
            }
        };
        window.addEventListener('message', onMessage);
        if (isEditorPreview) mockEditor();
        return () => window.removeEventListener('message', onMessage);
    }, []);

    // The message handler is registered once; route camera updates through a ref
    const updateCameraRef = useRef();
    updateCameraRef.current = (camera) => updateScene((s) => { s.camera = camera; return s; });

    // Free cam results go to the scene camera or to an intro shot ("intro:<i>:from|to" / "intro:new")
    const freecamResultRef = useRef();
    freecamResultRef.current = (target, cam) => {
        if (!target) return updateCameraRef.current(cam);
        if (target.startsWith('slot:')) {
            const i = Number(target.slice(5)) - 1;
            updateScene((s) => { if (s.slots[i]) s.slots[i].camera = cam; return s; });
            return;
        }
        const [, which, end] = target.split(':');
        updateScene((s) => {
            s.intro = s.intro || [];
            if (which === 'new') s.intro.push({ from: cam, to: clone(cam), duration: 6000 });
            else if (s.intro[Number(which)]) s.intro[Number(which)][end] = cam;
            return s;
        });
    };

    // ------- actions -------
    const close = () => fetchNui('editor:close');
    const save = () => fetchNui('editor:save', { scenes, active });
    const discard = () => { const d = JSON.parse(saved); setScenes(d.scenes); setActive(d.active); };
    const resetDefaults = () => { fetchNui('editor:save', { reset: true }); setConfirmReset(false); };

    const newScene = async (copyFrom) => {
        const base = copyFrom ? clone(copyFrom) : { label: 'New Scene', weather: 'EXTRASUNNY', time: { hour: 12, minute: 0 }, camera: null, slots: [] };
        let id = slug(base.label + (copyFrom ? ' copy' : ''));
        while (scenes.some((s) => s.id === id)) id = `${id}_${Math.floor(Math.random() * 1000)}`;
        base.id = id;
        base.label = copyFrom ? `${copyFrom.label} (copy)` : base.label;
        if (!copyFrom) {
            const p = await fetchNui('editor:myPosition');
            if (p) base.slots.push({ coords: { x: r2(p.x), y: r2(p.y), z: r2(p.z), w: wrap360(p.w) }, anim: { preset: animations[0]?.id } });
        }
        setScenes((l) => [...l, base]);
        setSceneId(id);
        setSlotIdx(0);
    };

    const deleteScene = () => {
        if (scenes.length <= 1) return;
        const rest = scenes.filter((s) => s.id !== sceneId);
        setScenes(rest);
        if (active === sceneId) setActive(rest[0].id);
        setSceneId(rest[0].id);
        setSlotIdx(0);
    };

    const addSlot = async () => {
        const p = await fetchNui('editor:myPosition');
        if (!p) return;
        updateScene((s) => {
            s.slots.push({ coords: { x: r2(p.x), y: r2(p.y), z: r2(p.z), w: wrap360(p.w) }, anim: { preset: animations[0]?.id } });
            return s;
        });
        setSlotIdx(scene.slots.length);
    };

    const placeHere = async () => {
        const p = await fetchNui('editor:myPosition');
        if (p) updateSlot((sl) => { sl.coords = { x: r2(p.x), y: r2(p.y), z: r2(p.z), w: wrap360(p.w) }; });
    };

    const removeSlot = () => {
        updateScene((s) => { s.slots.splice(slotIdx, 1); return s; });
        setSlotIdx(Math.max(0, slotIdx - 1));
    };

    const moveSlot = (dir) => {
        const j = slotIdx + dir;
        if (j < 0 || j >= scene.slots.length) return;
        updateScene((s) => { [s.slots[slotIdx], s.slots[j]] = [s.slots[j], s.slots[slotIdx]]; return s; });
        setSlotIdx(j);
    };

    const setCoord = (k, v) => updateSlot((sl) => { sl.coords[k] = k === 'w' ? wrap360(v) : r2(v); });
    const setCam = (k, v) => updateScene((s) => { s.camera[k] = r2(v); return s; });
    const autoToCustom = async () => {
        const c = await fetchNui('editor:autoCamera');
        if (c) updateCameraRef.current({ x: r2(c.x), y: r2(c.y), z: r2(c.z), rx: r2(c.rx), ry: 0, rz: r2(c.rz), fov: r2(c.fov) });
    };

    const togglePreview = () => fetchNui('editor:preview', { active: !preview });
    const walk = () => {
        setMode('walk');
        setPreview(false);
        fetchNui('editor:release');
        if (isEditorPreview) setTimeout(() => setMode('panel'), 1500);
    };
    const freecam = (target, start) => fetchNui('editor:freecam', { target, start });
    const shotCam = (i, end) => freecam(`intro:${i}:${end}`, scene.intro[i][end]);
    const addShot = () => freecam('intro:new', scene.intro?.at(-1)?.to);
    const setIntro = (fn) => updateScene((s) => { s.intro = fn(s.intro ? clone(s.intro) : []); if (!s.intro?.length) s.intro = null; return s; });
    const customiseIntro = async () => {
        const shots = await fetchNui('editor:autoIntro');
        if (shots) setIntro(() => shots.map((sh) => ({ ...sh, from: roundCam(sh.from), to: roundCam(sh.to) })));
    };
    const roundCam = (c) => ({ x: r2(c.x), y: r2(c.y), z: r2(c.z), rx: r2(c.rx), ry: 0, rz: r2(c.rz), fov: r2(c.fov) });
    const setSlotCam = (k, v) => updateSlot((sl) => { if (sl.camera) sl.camera[k] = k === 'rx' ? Math.max(-89, Math.min(89, r2(v))) : r2(v); });
    const frameSlot = async () => {
        const c = await fetchNui('editor:slotCamera', { index: slotIdx + 1 });
        if (c) updateSlot((sl) => { sl.camera = roundCam(c); });
    };

    // Peds move relative to the view; cameras move along their own heading.
    // Q/E turn left/right, T/G tilt a camera up/down.
    const moveCam = (cam, { forward = 0, right = 0, up = 0, turn = 0, pitch = 0 }) => {
        const h = (cam.rz * Math.PI) / 180;
        return {
            ...cam,
            x: r2(cam.x - Math.sin(h) * forward + Math.cos(h) * right),
            y: r2(cam.y + Math.cos(h) * forward + Math.sin(h) * right),
            z: r2(cam.z + up),
            rz: wrap360(cam.rz + turn),
            rx: Math.max(-89, Math.min(89, r2(cam.rx + pitch))),
        };
    };
    const nudge = async (d) => {
        if (keyTarget === 'scenecam') {
            if (scene?.camera) updateScene((s) => { s.camera = moveCam(s.camera, d); return s; });
        } else if (keyTarget === 'slotcam') {
            if (slot?.camera) updateSlot((sl) => { sl.camera = moveCam(sl.camera, d); });
        } else if (slot) {
            const yaw = Number(await fetchNui('editor:viewYaw')) || 0;
            const h = (yaw * Math.PI) / 180;
            const { forward = 0, right = 0, up = 0, turn = 0 } = d;
            updateSlot((sl) => {
                const c = sl.coords;
                sl.coords = {
                    x: r2(c.x - Math.sin(h) * forward + Math.cos(h) * right),
                    y: r2(c.y + Math.cos(h) * forward + Math.sin(h) * right),
                    z: r2(c.z + up),
                    w: wrap360(c.w + turn),
                };
            });
        }
    };

    useEffect(() => {
        const onKey = (e) => {
            if (!open || mode !== 'panel') return;
            const tag = e.target?.tagName;
            if (tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA') return;
            if (e.key === 'Escape') {
                if (playing) fetchNui('editor:stopIntro');
                else if (preview) togglePreview();
                else close();
                return;
            }
            if (playing) return;

            const mul = e.shiftKey ? 5 : e.ctrlKey ? 0.2 : 1;
            const m = step * mul, r = hStep * mul;
            const map = {
                w: { forward: m }, arrowup: { forward: m },
                s: { forward: -m }, arrowdown: { forward: -m },
                a: { right: -m }, arrowleft: { right: -m },
                d: { right: m }, arrowright: { right: m },
                r: { up: m }, pageup: { up: m },
                f: { up: -m }, pagedown: { up: -m },
                q: { turn: r }, e: { turn: -r },
                t: { pitch: r }, g: { pitch: -r },
            };
            const d = map[e.key.toLowerCase()];
            if (!d) return;
            e.preventDefault();
            nudge(d);
        };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    });

    if (!open) return null;

    if (mode === 'freecam') {
        return (
            <div className="ed-hint">
                <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> move · <kbd>Q</kbd>/<kbd>E</kbd> down/up · mouse look ·
                <kbd>Shift</kbd> fast · <kbd>Alt</kbd> slow · scroll FOV · <kbd>Enter</kbd> use view · <kbd>Backspace</kbd> cancel
            </div>
        );
    }

    return (
        <div id="editor" className={`${preview || playing ? 'previewing' : ''}${mode === 'walk' ? ' walking' : ''}`}>
            {playing && (
                <div className="ed-previewbar">
                    <span><i className="fa-solid fa-film" /> Playing intro</span>
                    <button className="ed-btn" onClick={() => fetchNui('editor:stopIntro')}>Stop <kbd>Esc</kbd></button>
                </div>
            )}
            {!playing && positions.map((p) => p.visible && (
                <div key={p.key} className={`ed-tag${p.key === slotIdx + 1 ? ' on' : ''}${scene?.slots[p.key - 1]?.camera ? ' cam' : ''}`} style={{ left: `${p.x}%`, top: `${p.y}%` }}
                    onClick={() => setSlotIdx(p.key - 1)}>
                    <span>Slot {p.key}</span>
                    <small>{scene?.slots[p.key - 1]?.camera ? 'Custom camera' : 'Empty slot'}</small>
                </div>
            ))}

            <div className="ed-walk-hint">
                <i className="fa-solid fa-person-walking" /> Walk to a spot, then press <kbd>E</kbd> to return to the editor
            </div>

            {!preview && !playing && mode !== 'walk' && (
                <div className="ed-livehint"><i className="fa-solid fa-location-dot" /> Live view · labels follow each ped</div>
            )}

            {preview && (
                <div className="ed-previewbar">
                    <span><i className="fa-solid fa-video" /> Previewing <b>{scene?.label}</b></span>
                    <span className="ed-keys"><kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> move · <kbd>R</kbd>/<kbd>F</kbd> up/down · <kbd>Q</kbd>/<kbd>E</kbd> turn{keyTarget !== 'ped' ? <> · <kbd>T</kbd>/<kbd>G</kbd> tilt</> : null}</span>
                    <button className="ed-btn" onClick={togglePreview}>Exit preview <kbd>Esc</kbd></button>
                </div>
            )}

            <aside className="ed-panel">
                <header>
                    <h1><i className="fa-solid fa-people-group" /> Character Scenes</h1>
                    <button className="ed-x" onClick={close} title="Close"><i className="fa-solid fa-xmark" /></button>
                </header>

                <div className="ed-body">
                    {/* ---- Scene ---- */}
                    <section>
                        <h3>Scene</h3>
                        <div className="ed-row">
                            <select value={sceneId || ''} onChange={(e) => { setSceneId(e.target.value); setSlotIdx(0); }}>
                                {scenes.map((s) => <option key={s.id} value={s.id}>{s.id === active ? '★ ' : ''}{s.label}</option>)}
                            </select>
                            <button className="ed-icon" title="New scene at my position" onClick={() => newScene()}><i className="fa-solid fa-plus" /></button>
                            <button className="ed-icon" title="Duplicate" disabled={!scene} onClick={() => newScene(scene)}><i className="fa-solid fa-clone" /></button>
                            <button className="ed-icon danger" title="Delete scene" disabled={scenes.length <= 1} onClick={deleteScene}><i className="fa-solid fa-trash" /></button>
                        </div>
                        {scene && (
                            <>
                                <label className="ed-field">Label<input value={scene.label} maxLength={40}
                                    onChange={(e) => updateScene((s) => { s.label = e.target.value; return s; })} /></label>
                                <div className="ed-row">
                                    <label className="ed-field">Weather
                                        <select value={scene.weather || ''} onChange={(e) => updateScene((s) => { s.weather = e.target.value || null; return s; })}>
                                            <option value="">Server weather</option>
                                            {weathers.map((w) => <option key={w} value={w}>{w}</option>)}
                                        </select>
                                    </label>
                                    <label className="ed-field small">Time
                                        <input type="time" value={scene.time ? `${String(scene.time.hour).padStart(2, '0')}:${String(scene.time.minute).padStart(2, '0')}` : ''}
                                            onChange={(e) => {
                                                const [h, m] = e.target.value.split(':').map(Number);
                                                updateScene((s) => { s.time = e.target.value ? { hour: h, minute: m } : null; return s; });
                                            }} />
                                    </label>
                                </div>
                                <button className={`ed-btn wide${scene.id === active ? ' on' : ''}`} disabled={scene.id === active} onClick={() => setActive(scene.id)}>
                                    <i className="fa-solid fa-star" /> {scene.id === active ? 'Active scene' : 'Make active scene'}
                                </button>
                            </>
                        )}
                    </section>

                    {/* ---- Camera ---- */}
                    {scene && (
                        <section>
                            <h3>Camera <em>{scene.camera ? 'custom' : 'auto-framed'}</em></h3>
                            <div className="ed-grid3">
                                <button className="ed-btn" onClick={() => freecam()}><i className="fa-solid fa-camera" /> Free cam</button>
                                <button className={`ed-btn${preview ? ' on' : ''}`} onClick={togglePreview}><i className="fa-solid fa-eye" /> Preview</button>
                                {scene.camera
                                    ? <button className="ed-btn" onClick={() => updateCameraRef.current(null)}><i className="fa-solid fa-wand-magic-sparkles" /> Auto</button>
                                    : <button className="ed-btn" onClick={autoToCustom}><i className="fa-solid fa-sliders" /> Tweak</button>}
                            </div>
                            {!scene.camera && (
                                <button className="ed-btn wide subtle" onClick={() => fetchNui('editor:reframe')}>
                                    <i className="fa-solid fa-expand" /> Re-frame auto camera to current slots
                                </button>
                            )}
                            {scene.camera && (
                                <div className="ed-nums">
                                    <Num label="X" value={scene.camera.x} step={step} onChange={(v) => setCam('x', v)} />
                                    <Num label="Y" value={scene.camera.y} step={step} onChange={(v) => setCam('y', v)} />
                                    <Num label="Z" value={scene.camera.z} step={step} onChange={(v) => setCam('z', v)} />
                                    <Num label="Pitch" value={scene.camera.rx} step={1} onChange={(v) => setCam('rx', Math.max(-89, Math.min(89, v)))} />
                                    <Num label="Yaw" value={scene.camera.rz} step={hStep} onChange={(v) => setCam('rz', v)} />
                                    <Num label="FOV" value={scene.camera.fov} step={1} onChange={(v) => setCam('fov', Math.max(10, Math.min(120, v)))} />
                                </div>
                            )}
                        </section>
                    )}

                    {/* ---- Intro shots ---- */}
                    {scene && (
                        <section>
                            <h3>Intro shots <em>{scene.intro?.length ? `${scene.intro.length} custom` : 'auto'}</em></h3>
                            <p className="ed-note">Played in a loop before character selection. Each shot cuts to its start and drifts to its end.</p>
                            {scene.intro?.map((sh, i) => (
                                <div className="ed-shot" key={i}>
                                    <b>{i + 1}</b>
                                    <button className="ed-btn" title="Set start with free cam" onClick={() => shotCam(i, 'from')}><i className="fa-solid fa-play" /> Start</button>
                                    <button className="ed-btn" title="Set end with free cam" onClick={() => shotCam(i, 'to')}><i className="fa-solid fa-flag-checkered" /> End</button>
                                    <label className="ed-dur" title="Duration (seconds)">
                                        <input type="number" min={1.5} max={30} step={0.5} value={sh.duration / 1000}
                                            onChange={(e) => setIntro((l) => { l[i].duration = Math.round(Math.min(30, Math.max(1.5, Number(e.target.value) || 6)) * 1000); return l; })} />s
                                    </label>
                                    <button className="ed-icon" title="Play this shot" onClick={() => fetchNui('editor:playIntro', { index: i + 1 })}><i className="fa-solid fa-eye" /></button>
                                    <button className="ed-icon danger" title="Remove shot" onClick={() => setIntro((l) => { l.splice(i, 1); return l; })}><i className="fa-solid fa-trash" /></button>
                                </div>
                            ))}
                            <div className="ed-grid3">
                                <button className="ed-btn" disabled={(scene.intro?.length || 0) >= 8} onClick={addShot}><i className="fa-solid fa-plus" /> Add shot</button>
                                <button className="ed-btn" onClick={() => fetchNui('editor:playIntro', {})}><i className="fa-solid fa-film" /> Play all</button>
                                {scene.intro?.length
                                    ? <button className="ed-btn" onClick={() => setIntro(() => [])}><i className="fa-solid fa-wand-magic-sparkles" /> Use auto</button>
                                    : <button className="ed-btn" onClick={customiseIntro}><i className="fa-solid fa-sliders" /> Customise</button>}
                            </div>
                        </section>
                    )}

                    {/* ---- Slots ---- */}
                    {scene && (
                        <section>
                            <h3>Character slots <em>{scene.slots.length}/12</em></h3>
                            <div className="ed-slots">
                                {scene.slots.map((s, i) => (
                                    <button key={i} className={i === slotIdx ? 'on' : ''} onClick={() => setSlotIdx(i)}>
                                        <b>{i + 1}</b>
                                        <span>{s.anim?.preset ? (animations.find((a) => a.id === s.anim.preset)?.label || s.anim.preset) : s.anim?.scenario || s.anim?.clip || 'No animation'}</span>
                                    </button>
                                ))}
                            </div>
                            <div className="ed-grid3">
                                <button className="ed-btn" disabled={scene.slots.length >= 12} onClick={addSlot}><i className="fa-solid fa-user-plus" /> Add here</button>
                                <button className="ed-btn" onClick={walk}><i className="fa-solid fa-person-walking" /> Walk mode</button>
                                <button className="ed-btn" onClick={() => fetchNui('editor:goto')}><i className="fa-solid fa-location-arrow" /> Go to</button>
                            </div>
                            <button className="ed-btn wide subtle" onClick={() => fetchNui('editor:return')}><i className="fa-solid fa-rotate-left" /> Return to where I was</button>
                        </section>
                    )}

                    {/* ---- Selected slot ---- */}
                    {slot && (
                        <section className="ed-slot">
                            <h3>
                                Slot {slotIdx + 1}
                                <span className="ed-slot-tools">
                                    <button className="ed-icon" title="Move up (lower slot number)" disabled={slotIdx === 0} onClick={() => moveSlot(-1)}><i className="fa-solid fa-arrow-up" /></button>
                                    <button className="ed-icon" title="Move down" disabled={slotIdx === scene.slots.length - 1} onClick={() => moveSlot(1)}><i className="fa-solid fa-arrow-down" /></button>
                                    <button className="ed-icon danger" title="Remove slot" onClick={removeSlot}><i className="fa-solid fa-trash" /></button>
                                </span>
                            </h3>
                            <p className="ed-note">Slot 1 shows the player's first character, slot 2 the second, and so on.</p>

                            <div className="ed-keybox">
                                <span>Keyboard moves</span>
                                <div className="ed-seg three">
                                    <button className={keyTarget === 'ped' ? 'on' : ''} onClick={() => setKeyTarget('ped')}>Ped</button>
                                    <button className={keyTarget === 'slotcam' ? 'on' : ''} disabled={!slot.camera}
                                        title={slot.camera ? '' : 'Give this slot a camera first'}
                                        onClick={() => { setKeyTarget('slotcam'); if (!preview) togglePreview(); }}>Slot cam</button>
                                    <button className={keyTarget === 'scenecam' ? 'on' : ''} disabled={!scene.camera}
                                        title={scene.camera ? '' : 'Tweak the scene camera first'}
                                        onClick={() => setKeyTarget('scenecam')}>Scene cam</button>
                                </div>
                                <small><kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> relative to view · <kbd>R</kbd>/<kbd>F</kbd> up/down · <kbd>Q</kbd>/<kbd>E</kbd> turn · <kbd>T</kbd>/<kbd>G</kbd> tilt cam · <kbd>Shift</kbd> ×5 · <kbd>Ctrl</kbd> fine</small>
                            </div>
                            <div className="ed-row steps">
                                <span>Step</span>
                                {[0.01, 0.05, 0.1, 0.5].map((v) => <button key={v} className={step === v ? 'on' : ''} onClick={() => setStep(v)}>{v}m</button>)}
                                <span>Rot</span>
                                {[1, 5, 15].map((v) => <button key={v} className={hStep === v ? 'on' : ''} onClick={() => setHStep(v)}>{v}°</button>)}
                            </div>
                            <div className="ed-nums">
                                <Num label="X" value={slot.coords.x} step={step} onChange={(v) => setCoord('x', v)} />
                                <Num label="Y" value={slot.coords.y} step={step} onChange={(v) => setCoord('y', v)} />
                                <Num label="Z" value={slot.coords.z} step={step} onChange={(v) => setCoord('z', v)} />
                                <Num label="Heading" value={slot.coords.w} step={hStep} onChange={(v) => setCoord('w', v)} />
                            </div>
                            <button className="ed-btn wide" onClick={placeHere}><i className="fa-solid fa-crosshairs" /> Place at my position</button>

                            <h4>Slot camera <em>{slot.camera ? 'custom' : 'auto focus'}</em></h4>
                            <p className="ed-note">Used when a player selects this slot. The wide scene camera still shows every ped.</p>
                            <div className="ed-grid3">
                                <button className="ed-btn" onClick={() => freecam(`slot:${slotIdx + 1}`, slot.camera || undefined)}><i className="fa-solid fa-camera" /> Place</button>
                                <button className="ed-btn" onClick={frameSlot}><i className="fa-solid fa-crosshairs" /> Frame ped</button>
                                {slot.camera
                                    ? <button className="ed-btn" onClick={() => updateSlot((sl) => { sl.camera = null; })}><i className="fa-solid fa-wand-magic-sparkles" /> Auto</button>
                                    : <button className="ed-btn" onClick={togglePreview}><i className="fa-solid fa-eye" /> Preview</button>}
                            </div>
                            {slot.camera && (
                                <div className="ed-nums">
                                    <Num label="X" value={slot.camera.x} step={step} onChange={(v) => setSlotCam('x', v)} />
                                    <Num label="Y" value={slot.camera.y} step={step} onChange={(v) => setSlotCam('y', v)} />
                                    <Num label="Z" value={slot.camera.z} step={step} onChange={(v) => setSlotCam('z', v)} />
                                    <Num label="Pitch" value={slot.camera.rx} step={1} onChange={(v) => setSlotCam('rx', v)} />
                                    <Num label="Yaw" value={slot.camera.rz} step={hStep} onChange={(v) => setSlotCam('rz', v)} />
                                    <Num label="FOV" value={slot.camera.fov} step={1} onChange={(v) => setSlotCam('fov', Math.max(10, Math.min(120, v)))} />
                                </div>
                            )}

                            <h4>Animation</h4>
                            <AnimEditor
                                anim={slot.anim}
                                animations={animations}
                                onChange={(a) => updateSlot((sl) => { sl.anim = a; })}
                                onReplay={() => fetchNui('editor:replay', { index: slotIdx + 1 })}
                            />
                        </section>
                    )}
                </div>

                <footer>
                    {confirmReset ? (
                        <div className="ed-confirm">
                            <span>Replace all scenes with config.lua defaults?</span>
                            <button className="ed-btn" onClick={() => setConfirmReset(false)}>No</button>
                            <button className="ed-btn danger" onClick={resetDefaults}>Reset</button>
                        </div>
                    ) : (
                        <>
                            <button className="ed-btn subtle" onClick={() => setConfirmReset(true)} title="Reset to config.lua defaults"><i className="fa-solid fa-clock-rotate-left" /></button>
                            <span className={`ed-dirty${dirty ? ' on' : ''}`}>{dirty ? 'Unsaved changes' : 'All saved'}</span>
                            <button className="ed-btn" disabled={!dirty} onClick={discard}>Discard</button>
                            <button className="ed-btn primary" disabled={!dirty} onClick={save}><i className="fa-solid fa-floppy-disk" /> Save</button>
                        </>
                    )}
                </footer>
            </aside>
        </div>
    );
}
