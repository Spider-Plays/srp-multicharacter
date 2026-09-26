export const isBrowser = !window.invokeNative;
export const isEditorPreview = isBrowser && location.search.includes('editor');

const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'srp-multicharacter';

export function fetchNui(name, data = {}) {
    if (isBrowser) return Promise.resolve(mockResponse(name, data));
    return fetch(`https://${resource}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    })
        .then((r) => r.json())
        .catch(() => null);
}

export const money = (n) =>
    new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(n || 0);

// ---------------------------------------------------------------------------
// Browser mocks for `npm run dev` (selector at /, configurator at /?editor)
// ---------------------------------------------------------------------------

const post = (msg, delay = 0) => setTimeout(() => window.postMessage(msg, '*'), delay);

const mockEntries = [
    { citizenid: 'ABC12345', firstname: 'Tony', lastname: 'Marino', gender: 0, birthdate: '1988-04-12', nationality: 'Italian', cash: 2450, bank: 184320, job: 'Los Santos Police', grade: 'Sergeant' },
    { citizenid: 'XYZ67890', firstname: 'Mia', lastname: 'Kowalski', gender: 1, birthdate: '1995-11-02', nationality: 'American', cash: 380, bank: 12650, job: 'EMS', grade: 'Paramedic' },
    false,
];

export function mockSelector() {
    post({ action: 'open', entries: mockEntries, sceneSlots: 3, selected: 1, canDelete: true, intro: { title: 'Spider Roleplay', subtitle: 'Welcome Back', prompt: 'Press ENTER to continue' } });
    post({ action: 'positions', items: [
        { key: 1, visible: true, x: 28, y: 30 },
        { key: 2, visible: true, x: 52, y: 34 },
        { key: 3, visible: true, x: 74, y: 40 },
    ] }, 50);
}

const mockAnims = [
    { id: 'idle', label: 'Idle', kind: 'anim' },
    { id: 'crossarms', label: 'Arms Crossed', kind: 'anim' },
    { id: 'sitchair', label: 'Sit (Chair)', kind: 'anim' },
    { id: 'phone', label: 'On Phone', kind: 'scenario' },
];

export function mockEditor() {
    post({ action: 'editorPositions', items: [
        { key: 1, visible: true, x: 28, y: 46 },
        { key: 2, visible: true, x: 46, y: 40 },
        { key: 3, visible: true, x: 62, y: 50 },
    ] }, 80);
    post({
        action: 'openEditor',
        active: 'arcadius',
        animations: mockAnims,
        weathers: ['EXTRASUNNY', 'CLEAR', 'RAIN'],
        scenes: [{
            id: 'arcadius', label: 'Arcadius Office', weather: 'EXTRASUNNY', time: { hour: 19, minute: 30 }, camera: null,
            slots: [
                { coords: { x: -136.85, y: -641.48, z: 167.82, w: 149.54 }, anim: { preset: 'crossarms' } },
                { coords: { x: -126.07, y: -641.27, z: 167.82, w: 111.23 }, anim: { preset: 'phone' } },
                { coords: { x: -125.86, y: -632.94, z: 168.52, w: 190.29 }, anim: { preset: 'sitchair' } },
            ],
        }],
    });
}

function mockResponse(name, data) {
    console.log('[nui]', name, data);
    if (name === 'editor:myPosition') return { x: -130 + Math.random() * 5, y: -638 + Math.random() * 5, z: 167.82, w: Math.random() * 360 };
    if (name === 'editor:autoCamera') return { x: -133.07, y: -644.64, z: 168.5, rx: -3, ry: 0, rz: 209.7, fov: 50 };
    if (name === 'editor:slotCamera') return { x: -140.2, y: -638.4, z: 168.2, rx: -3.5, ry: 0, rz: 160, fov: 38 };
    if (name === 'editor:freecam') post({ action: 'editorFreecam', active: false, target: data.target, camera: { x: -134.2, y: -646.1, z: 168.9, rx: -6.5, ry: 0, rz: 205.3, fov: 45 } }, 400);
    if (name === 'create') return { ok: true };
    if (name === 'play' || name === 'delete') return true;
    return 'ok';
}
