const canvas = document.getElementById("canvas");
const init_w = canvas.width;
const init_h = canvas.height;
let width = canvas.width;
let height = canvas.height;
let fullscreen = false;

const ctx = canvas.getContext("2d");

function fullscreenMode(mode) {
    fullscreen = mode;
    if (fullscreen) {
        if (canvas.requestFullscreen) {
            canvas.requestFullscreen();
        }
        canvas.width = window.innerWidth;
        canvas.height = window.innerHeight;
        resize(canvas.width, canvas.height);
    } else {
        if (document.exitFullscreen) {
            document.exitFullscreen();
        }
    }
}

function toggleFullscreen() {
    fullscreenMode(!fullscreen);
}

let memory = null;
const imports = {
    env: {
        _fullscreen: (val) => {
            fullscreenMode(val != 0);
        },

        _seed: () => {
            return Math.floor(Math.random() * 0xFFFFFFFF);
        },

        _print: (pointer, length) => { 
            const arr = new Uint8Array(memory.buffer, pointer, length);
            const str = new TextDecoder().decode(arr);
            console.log(str);
        },
    },
};
const wasm = await WebAssembly.instantiateStreaming(fetch("zig-out/lib/freecell.wasm"), imports);
memory = wasm.instance.exports.memory;

const _init = wasm.instance.exports._init;
const _frame = wasm.instance.exports._frame;
const _resize = wasm.instance.exports._resize;
const _fullscreen_mode = wasm.instance.exports._fullscreen_mode;

let image_ptr = _init(width, height);
let imageDataArray = new Uint8ClampedArray(memory.buffer, image_ptr, 4 * width * height);
let imageData = new ImageData(imageDataArray, width, height);

function resize(nwidth, nheight) {
    width = nwidth;
    height = nheight;
    image_ptr = _resize(width, height);
    imageDataArray = new Uint8ClampedArray(memory.buffer, image_ptr, 4 * width * height);
    imageData = new ImageData(imageDataArray, width, height);
}

let mouseX = 0;
let mouseY = 0;
let mousePressed = false;
let mouseInside = false;

document.addEventListener("fullscreenchange", function() {
    if (document.fullscreenElement === null) {
        canvas.width = init_w;
        canvas.height = init_h;
        resize(canvas.width, canvas.height);
        _fullscreen_mode(false);
    }
});

canvas.addEventListener('mousemove', (e) => {
    let rect = canvas.getBoundingClientRect();
    mouseX = e.clientX - rect.left;
    mouseY = e.clientY - rect.top;
    mouseInside = true;
});

canvas.addEventListener('mouseout', () => {
    mousePressed = false;
    mouseInside = false;
});

canvas.addEventListener('mousedown', (e) => {
    if (e.button === 0) {
        console.log("button")
        mousePressed = true;
    }
    e.preventDefault();
});

canvas.addEventListener("contextmenu", (e) => {
    e.preventDefault();
});

canvas.addEventListener('mouseup', (e) => {
    if (e.button === 0) {
        mousePressed = false;
    }
});

function frame() {
    // const startTime = performance.now();

    _frame(mouseX, mouseY, mouseInside, mousePressed, performance.now());
    ctx.putImageData(imageData, 0, 0);

    // const endTime = performance.now();
    // const timeDifference = endTime - startTime;
    // console.log(`${1000.0 / timeDifference} hz`);

    requestAnimationFrame(frame);
}

frame();