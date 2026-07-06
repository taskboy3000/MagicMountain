(function () {
    'use strict';

    var ctx = null;
    var masterGain = null;
    var noiseSource = null;
    var droneOsc = null;
    var lfo = null;
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
        masterGain.gain.value = 1;
        masterGain.connect(ctx.destination);

        var buf = randomBuf(4, ctx.sampleRate);
        noiseSource = ctx.createBufferSource();
        noiseSource.buffer = buf;
        noiseSource.loop = true;

        var lowpass = ctx.createBiquadFilter();
        lowpass.type = 'lowpass';
        lowpass.frequency.value = 800;
        lowpass.Q.value = 1;

        lfo = ctx.createOscillator();
        lfo.frequency.value = 0.15;
        var lfoGain = ctx.createGain();
        lfoGain.gain.value = 300;
        lfo.connect(lfoGain);
        lfoGain.connect(lowpass.frequency);
        lfo.start();

        noiseSource.connect(lowpass);
        lowpass.connect(masterGain);
        noiseSource.start();

        droneOsc = ctx.createOscillator();
        droneOsc.type = 'sine';
        droneOsc.frequency.value = 38;
        var droneGain = ctx.createGain();
        droneGain.gain.value = 0.08;
        droneOsc.connect(droneGain);
        droneGain.connect(masterGain);
        droneOsc.start();

        scheduleNextChirp();
    }

    function scheduleNextChirp() {
        var delay = 20000 + Math.random() * 20000;
        var id = setTimeout(function () {
            playChirp();
            var idx = timerIds.indexOf(id);
            if (idx !== -1) timerIds.splice(idx, 1);
            if (!stopped) scheduleNextChirp();
        }, delay);
        timerIds.push(id);
    }

    function playChirp() {
        if (!ctx || stopped) return;
        var burst = randomBuf(0.08, ctx.sampleRate);
        var source = ctx.createBufferSource();
        source.buffer = burst;

        var bandpass = ctx.createBiquadFilter();
        bandpass.type = 'bandpass';
        bandpass.frequency.value = 2000;
        bandpass.Q.value = 15;

        var chirpGain = ctx.createGain();
        chirpGain.gain.value = 0.15;

        source.connect(bandpass);
        bandpass.connect(chirpGain);
        chirpGain.connect(masterGain);
        source.start();
    }

    function onVisibilityChange() {
        if (!ctx || stopped) return;
        if (document.hidden) {
            ctx.suspend();
        } else {
            ctx.resume();
        }
    }

    function setupGestureListener() {
        var input = document.getElementById('display-name');
        if (!input) return;
        input.addEventListener('pointerdown', function () {
            init();
            if (ctx && ctx.state === 'suspended') ctx.resume();
        }, { once: true });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', setupGestureListener);
    } else {
        setupGestureListener();
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
        }, durationMs || 500);
    };
}());
