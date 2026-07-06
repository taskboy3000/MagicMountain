(function () {
    'use strict';

    var ctx = null;
    var masterGain = null;
    var noiseSource = null;
    var droneOsc = null;
    var lfo = null;
    var noisePanner = null;
    var noisePanLfo = null;
    var chirpPanner = null;
    var panLfo = null;
    var timerIds = [];
    var stopped = false;

    function randomBuf(sec, sampleRate) {
        var len = sampleRate * sec;
        var buf = ctx.createBuffer(1, len, sampleRate);
        var d = buf.getChannelData(0);
        for (var i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
        return buf;
    }

    function init() {
        if (ctx) return;
        try {
            ctx = new AudioContext();
        } catch (e) {
            return;
        }

        masterGain = ctx.createGain();
        masterGain.gain.value = 0.25;
        masterGain.connect(ctx.destination);

        var buf = randomBuf(4, ctx.sampleRate);
        noiseSource = ctx.createBufferSource();
        noiseSource.buffer = buf;
        noiseSource.loop = true;

        var lowpass = ctx.createBiquadFilter();
        lowpass.type = 'lowpass';
        lowpass.frequency.value = 800;
        lowpass.Q.value = 2;

        lfo = ctx.createOscillator();
        lfo.frequency.value = 0.075;
        var lfoGain = ctx.createGain();
        lfoGain.gain.value = 600;
        lfo.connect(lfoGain);
        lfoGain.connect(lowpass.frequency);
        lfo.start();

        noisePanner = ctx.createStereoPanner();
        noisePanner.pan.value = 0;

        noisePanLfo = ctx.createOscillator();
        noisePanLfo.type = 'sine';
        noisePanLfo.frequency.value = 0.015;
        var noisePanGain = ctx.createGain();
        noisePanGain.gain.value = 0.5;
        noisePanLfo.connect(noisePanGain);
        noisePanGain.connect(noisePanner.pan);
        noisePanLfo.start();

        noiseSource.connect(lowpass);
        lowpass.connect(noisePanner);
        noisePanner.connect(masterGain);
        noiseSource.start();

        droneOsc = ctx.createOscillator();
        droneOsc.type = 'sine';
        droneOsc.frequency.value = 38;
        var droneGain = ctx.createGain();
        droneGain.gain.value = 0.08;
        droneOsc.connect(droneGain);
        droneGain.connect(masterGain);
        droneOsc.start();

        chirpPanner = ctx.createStereoPanner();
        chirpPanner.pan.value = 0;
        chirpPanner.connect(masterGain);

        panLfo = ctx.createOscillator();
        panLfo.type = 'sine';
        panLfo.frequency.value = 0.03;
        var panLfoGain = ctx.createGain();
        panLfoGain.gain.value = 0.75;
        panLfo.connect(panLfoGain);
        panLfoGain.connect(chirpPanner.pan);
        panLfo.start();

        scheduleNextChirp();
    }

    function scheduleNextChirp() {
        var delay = 10000 + Math.random() * 10000;
        var id = setTimeout(function () {
            playChirp();
            var idx = timerIds.indexOf(id);
            if (idx !== -1) timerIds.splice(idx, 1);
            if (!stopped) scheduleNextChirp();
        }, delay);
        timerIds.push(id);
    }

    function playChirp() {
        if (!ctx || stopped || !chirpPanner) return;
        var numNotes = 1 + Math.floor(Math.random() * 3);
        var baseTime = ctx.currentTime;
        for (var i = 0; i < numNotes; i++) {
            var noteTime = baseTime + (i === 0 ? 0 : 0.5 + Math.random() * 0.75);
            var freq = 4000 + Math.random() * 4000;
            var vol = 0.6 * Math.pow(0.7, i);
            var dur = 0.04 + Math.random() * 0.04;
            var burst = randomBuf(dur, ctx.sampleRate);
            var source = ctx.createBufferSource();
            source.buffer = burst;
            var bandpass = ctx.createBiquadFilter();
            bandpass.type = 'bandpass';
            bandpass.frequency.value = freq;
            bandpass.Q.value = 15;
            var noteGain = ctx.createGain();
            noteGain.gain.value = vol;
            source.connect(bandpass);
            bandpass.connect(noteGain);
            noteGain.connect(chirpPanner);
            source.start(noteTime);
            source.stop(noteTime + dur);
        }
    }

    function onVisibilityChange() {
        if (!ctx || stopped) return;
        if (document.hidden) {
            ctx.suspend();
        } else {
            ctx.resume();
        }
    }

    var started = false;

    function startOnGesture() {
        if (started) return;
        started = true;
        init();
        if (ctx && ctx.state === 'suspended') ctx.resume();
    }

    function setupGestureListener() {
        document.addEventListener('click', startOnGesture);
        document.addEventListener('keydown', startOnGesture);
    }

    setupGestureListener();

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', setupGestureListener);
    }
    document.addEventListener('visibilitychange', onVisibilityChange);

    window.stopAmbient = function (durationMs) {
        if (!ctx || stopped) return;
        stopped = true;

        timerIds.forEach(clearTimeout);
        timerIds = [];

        document.removeEventListener('visibilitychange', onVisibilityChange);

        var dur = (durationMs || 500) / 1000;
        masterGain.gain.linearRampToValueAtTime(0, ctx.currentTime + dur);

        setTimeout(function () {
            try { if (noiseSource) noiseSource.stop(); } catch (e) { /* ok */ }
            try { if (droneOsc) droneOsc.stop(); } catch (e) { /* ok */ }
            try { if (lfo) lfo.stop(); } catch (e) { /* ok */ }
            try { if (noisePanLfo) noisePanLfo.stop(); } catch (e) { /* ok */ }
            try { if (panLfo) panLfo.stop(); } catch (e) { /* ok */ }
        }, durationMs || 500);
    };
}());
