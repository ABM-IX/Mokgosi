import React from 'react';
import {createRoot} from 'react-dom/client';
import App from './App.jsx';
import '@fontsource-variable/inter';
import '@fontsource/jetbrains-mono/400.css';
import '@fontsource/jetbrains-mono/500.css';
import './style.css';
createRoot(document.getElementById('root')).render(<React.StrictMode><App/></React.StrictMode>);
