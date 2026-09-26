import { useEffect, useState } from 'react';
import { fetchNui, isBrowser, isEditorPreview, mockSelector, money } from './nui';

const fullName = (c) => `${c.firstname} ${c.lastname}`;

function age(birthdate) {
    const d = new Date(birthdate);
    if (Number.isNaN(d.getTime())) return null;
    const now = new Date();
    let a = now.getFullYear() - d.getFullYear();
    if (now < new Date(now.getFullYear(), d.getMonth(), d.getDate())) a--;
    return a;
}

function FloatingCard({ entry, index, pos, selected, onSelect }) {
    const style = { left: `${pos.x}%`, top: `${pos.y}%` };
    const cls = `float-card${selected ? ' selected' : ' ghost'}${entry ? '' : ' empty'}`;

    if (!entry) {
        return (
            <button className={cls} style={style} onClick={() => onSelect(index)}>
                <i className="fa-solid fa-plus" />
                <span className="empty-label">New Character</span>
            </button>
        );
    }
    return (
        <button className={cls} style={style} onClick={() => onSelect(index)}>
            <span className="fc-name">{fullName(entry)}</span>
            <span className="fc-job">
                <i className="fa-solid fa-briefcase" /> {entry.job}{entry.grade ? ` · ${entry.grade}` : ''}
            </span>
            <span className="fc-money">
                <span><i className="fa-solid fa-money-bill-wave" /> {money(entry.cash)}</span>
                <span><i className="fa-solid fa-building-columns" /> {money(entry.bank)}</span>
            </span>
        </button>
    );
}

function Field({ icon, label, children }) {
    return (
        <label className="cr-field">
            <span className="cr-label">{label}</span>
            <span className="cr-input">
                <i className={`fa-solid fa-${icon}`} />
                {children}
            </span>
        </label>
    );
}

function CreateModal({ slot, onClose, onSubmit, error, busy }) {
    const [form, setForm] = useState({ firstname: '', lastname: '', birthdate: '', gender: 'male', nationality: '' });
    const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });
    const years = form.birthdate ? age(form.birthdate) : null;
    const ready = form.firstname.trim().length >= 2 && form.lastname.trim().length >= 2 && form.birthdate;

    return (
        <div className="modal-back" onClick={onClose}>
            <form className="create" onClick={(e) => e.stopPropagation()} onSubmit={(e) => { e.preventDefault(); onSubmit(form); }}>
                <div className="cr-form">
                    <header className="cr-head">
                        <span className="cr-kicker">Slot {String(slot).padStart(2, '0')} · Citizen registration</span>
                        <h2>Who are you?</h2>
                    </header>

                    <div className="row2">
                        <Field icon="user" label="First name">
                            <input autoFocus maxLength={16} placeholder="John" value={form.firstname} onChange={set('firstname')} />
                        </Field>
                        <Field icon="signature" label="Last name">
                            <input maxLength={16} placeholder="Doe" value={form.lastname} onChange={set('lastname')} />
                        </Field>
                    </div>
                    <div className="row2">
                        <Field icon="cake-candles" label="Date of birth">
                            <input type="date" min="1900-01-01" value={form.birthdate} onChange={set('birthdate')} />
                        </Field>
                        <Field icon="earth-americas" label="Nationality">
                            <input maxLength={30} placeholder="American" value={form.nationality} onChange={set('nationality')} />
                        </Field>
                    </div>

                    <div className="cr-field">
                        <span className="cr-label">Sex</span>
                        <div className="gender">
                            {['male', 'female'].map((g) => (
                                <button type="button" key={g} className={form.gender === g ? 'on' : ''} onClick={() => setForm({ ...form, gender: g })}>
                                    <i className={`fa-solid fa-${g === 'male' ? 'mars' : 'venus'}`} />
                                    <span>{g === 'male' ? 'Male' : 'Female'}</span>
                                </button>
                            ))}
                        </div>
                    </div>

                    {error && <p className="error"><i className="fa-solid fa-circle-exclamation" /> {error}</p>}

                    <div className="modal-actions">
                        <button type="button" className="btn ghost-btn" onClick={onClose}>Cancel</button>
                        <button type="submit" className="btn primary big" disabled={busy || !ready}>
                            {busy ? <i className="fa-solid fa-spinner fa-spin" /> : <>Begin <i className="fa-solid fa-arrow-right" /></>}
                        </button>
                    </div>
                </div>

                <aside className="cr-preview">
                    <div className="idcard">
                        <div className="id-top">
                            <span>State of San Andreas</span>
                            <b>Identification</b>
                        </div>
                        <div className="id-body">
                            <div className="id-photo"><i className={`fa-solid fa-${form.gender === 'female' ? 'person-dress' : 'person'}`} /></div>
                            <dl>
                                <dt>Surname</dt><dd>{form.lastname || '—'}</dd>
                                <dt>Given name</dt><dd>{form.firstname || '—'}</dd>
                                <dt>DOB</dt><dd>{form.birthdate || '—'}{years != null && years >= 0 ? ` · ${years}y` : ''}</dd>
                                <dt>Nationality</dt><dd>{form.nationality || 'American'}</dd>
                                <dt>Sex</dt><dd>{form.gender === 'female' ? 'F' : 'M'}</dd>
                            </dl>
                        </div>
                        <div className="id-sign">{`${form.firstname} ${form.lastname}`.trim() || ' '}</div>
                    </div>
                    <p>You'll design your look right after this.</p>
                </aside>
            </form>
        </div>
    );
}

function DeleteModal({ entry, onClose, onConfirm, busy }) {
    const [typed, setTyped] = useState('');
    const ok = typed.trim().toLowerCase() === entry.firstname.toLowerCase();
    return (
        <div className="modal-back" onClick={onClose}>
            <form className="modal danger" onClick={(e) => e.stopPropagation()} onSubmit={(e) => { e.preventDefault(); if (ok) onConfirm(); }}>
                <h2>Delete {fullName(entry)}?</h2>
                <p>This permanently removes the character, their money, items and vehicles. It cannot be undone.</p>
                <label>Type <b>{entry.firstname}</b> to confirm<input autoFocus value={typed} onChange={(e) => setTyped(e.target.value)} /></label>
                <div className="modal-actions">
                    <button type="button" className="btn ghost-btn" onClick={onClose}>Cancel</button>
                    <button type="submit" className="btn danger-btn" disabled={!ok || busy}>Delete forever</button>
                </div>
            </form>
        </div>
    );
}

export default function App() {
    const [visible, setVisible] = useState(false);
    const [entries, setEntries] = useState([]);
    const [sceneSlots, setSceneSlots] = useState(0);
    const [canDelete, setCanDelete] = useState(true);
    const [selected, setSelected] = useState(1);
    const [positions, setPositions] = useState({});
    const [modal, setModal] = useState(null);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState('');
    const [intro, setIntro] = useState(null);

    const finishIntro = () => {
        if (!intro) return;
        setIntro(null);
        fetchNui('introDone');
    };

    const entry = entries[selected - 1];

    const select = (i) => {
        if (busy || i < 1 || i > entries.length) return;
        setSelected(i);
        setModal(null);
        fetchNui('select', { index: i });
    };

    const play = async () => {
        if (!entry || busy) return;
        setBusy(true);
        const ok = await fetchNui('play', { index: selected });
        if (!ok || isBrowser) setBusy(false);
    };

    const create = async (form) => {
        setBusy(true);
        setError('');
        const res = await fetchNui('create', { index: selected, ...form });
        if (!res?.ok) {
            setError(res?.error || 'Something went wrong.');
            setBusy(false);
        } else if (isBrowser) {
            setBusy(false);
            setModal(null);
        }
    };

    const remove = async () => {
        setBusy(true);
        await fetchNui('delete', { index: selected });
        setBusy(false);
        setModal(null);
    };

    useEffect(() => {
        const onMessage = ({ data }) => {
            if (data.action === 'open') {
                setEntries(data.entries || []);
                setSceneSlots(data.sceneSlots || 0);
                setCanDelete(data.canDelete !== false);
                setSelected(data.selected || 1);
                setModal(null);
                setBusy(false);
                setIntro(data.intro || null);
                setVisible(true);
            } else if (data.action === 'positions') {
                const map = {};
                for (const p of data.items) map[p.key] = p;
                setPositions(map);
            } else if (data.action === 'close') {
                setVisible(false);
                setModal(null);
            }
        };
        window.addEventListener('message', onMessage);
        if (isBrowser && !isEditorPreview) mockSelector();
        return () => window.removeEventListener('message', onMessage);
    }, []);

    useEffect(() => {
        const onKey = (e) => {
            if (!visible || busy) return;
            if (intro) {
                if (e.key === 'Enter' || e.key === ' ') finishIntro();
                return;
            }
            if (modal) {
                if (e.key === 'Escape') setModal(null);
                return;
            }
            if (e.key === 'ArrowLeft') select(selected - 1);
            else if (e.key === 'ArrowRight') select(selected + 1);
            else if (e.key === 'Enter') entry ? play() : setModal('create');
        };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    });

    return (
        <div id="selector" className={`${visible ? '' : 'hidden'}${intro ? ' intro-on' : ''}`}>
            <div className="vignette" />

            <div className="letterbox top" />
            <div className="letterbox bottom" />

            {intro && (
                <div className="intro" onClick={finishIntro}>
                    <div className="intro-center">
                        <span className="intro-line" />
                        <h1 className="intro-title">{intro.title}</h1>
                        <span className="intro-line" />
                        <h2 className="intro-sub">{intro.subtitle}</h2>
                    </div>
                    <p className="intro-prompt">{intro.prompt}</p>
                </div>
            )}

            <div className="sel-ui">

            <header className="sel-title">
                <h1>Select Character</h1>
                <p><kbd>←</kbd><kbd>→</kbd> browse · <kbd>Enter</kbd> play</p>
            </header>

            {entries.map((e, i) => {
                const idx = i + 1;
                const pos = positions[idx];
                if (idx > sceneSlots || !pos?.visible) return null;
                return <FloatingCard key={idx} index={idx} entry={e} pos={pos} selected={idx === selected} onSelect={select} />;
            })}

            <footer className="dock">
                {entry ? (
                    <div className="details" key={selected}>
                        <div className="who">
                            <h2>{fullName(entry)}</h2>
                            <div className="meta">
                                <span><i className="fa-solid fa-id-card" /> {entry.citizenid}</span>
                                {entry.birthdate && <span><i className="fa-solid fa-cake-candles" /> {entry.birthdate}{age(entry.birthdate) != null ? ` (${age(entry.birthdate)})` : ''}</span>}
                                {entry.nationality && <span><i className="fa-solid fa-flag" /> {entry.nationality}</span>}
                                <span><i className={`fa-solid fa-${entry.gender === 1 ? 'venus' : 'mars'}`} /></span>
                            </div>
                        </div>
                        <div className="actions">
                            {canDelete && (
                                <button className="btn icon danger-btn" title="Delete character" onClick={() => setModal('delete')} disabled={busy}>
                                    <i className="fa-solid fa-trash" />
                                </button>
                            )}
                            <button className="btn primary big" onClick={play} disabled={busy}>
                                {busy ? <i className="fa-solid fa-spinner fa-spin" /> : <>Play <i className="fa-solid fa-play" /></>}
                            </button>
                        </div>
                    </div>
                ) : entry === false ? (
                    <div className="details" key={selected}>
                        <div className="who">
                            <h2 className="muted">Empty slot</h2>
                            <div className="meta"><span>Start a new story in Los Santos.</span></div>
                        </div>
                        <div className="actions">
                            <button className="btn primary big" onClick={() => { setError(''); setModal('create'); }} disabled={busy}>
                                Create <i className="fa-solid fa-plus" />
                            </button>
                        </div>
                    </div>
                ) : null}
            </footer>
            </div>

            {modal === 'create' && <CreateModal slot={selected} onClose={() => !busy && setModal(null)} onSubmit={create} error={error} busy={busy} />}
            {modal === 'delete' && entry && <DeleteModal entry={entry} onClose={() => !busy && setModal(null)} onConfirm={remove} busy={busy} />}
        </div>
    );
}
