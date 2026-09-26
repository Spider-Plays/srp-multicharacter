import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
    plugins: [react()],
    base: './', // NUI loads files relative to the resource
    build: { outDir: 'build', emptyOutDir: true },
    server: { port: 5173, open: true },
});
