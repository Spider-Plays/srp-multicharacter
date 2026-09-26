import { createRoot } from 'react-dom/client';
import App from './App';
import Editor from './Editor';
import { isBrowser, isEditorPreview } from './nui';
import './App.css';
import './Editor.css';

// Stand-in for the game world when previewing in a normal browser
if (isBrowser) {
    document.body.style.background = isEditorPreview
        ? 'linear-gradient(160deg, #5d7a8c, #2c3a42)'
        : 'radial-gradient(ellipse at 50% 40%, #4a4f57, #16181c)';
}

createRoot(document.getElementById('root')).render(
    <>
        <App />
        <Editor />
    </>
);
