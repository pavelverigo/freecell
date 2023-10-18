const canvas = document.getElementById("canvas");
const width = canvas.width;
const height = canvas.height;

const ctx = canvas.getContext("2d");

let memory = null;
const imports = {
    env: {
        textout: (result) => { 
            document.getElementById("text").innerHTML = `Print: ${result}`;
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

const add = wasm.instance.exports.add;
add(1, 2);

const _init = wasm.instance.exports._init;
const _frame = wasm.instance.exports._frame;

const image_ptr = _init(width, height);
const imageDataArray = new Uint8ClampedArray(memory.buffer, image_ptr, 4 * width * height);
const imageData = new ImageData(imageDataArray, width, height);

let mouseX = 0;
let mouseY = 0;
let mousePressed = false;
let mouseInside = false;

canvas.addEventListener('mousemove', (e) => {
    let rect = canvas.getBoundingClientRect();
    mouseX = e.clientX - rect.left;
    mouseY = e.clientY - rect.top;
    mouseInside = true;
});

canvas.addEventListener('mouseout', () => {
    mouseInside = false;
});

canvas.addEventListener('mousedown', (e) => {
    if (e.button === 0) {
        mousePressed = true;
    }
});

canvas.addEventListener('mouseup', (e) => {
    if (e.button === 0) {
        mousePressed = false;
    }
});

function frame() {
    // const startTime = performance.now();

    _frame(mouseX, mouseY, mouseInside, mousePressed);
    ctx.putImageData(imageData, 0, 0);

    // const endTime = performance.now();
    // const timeDifference = endTime - startTime;
    // console.log(`${1000.0 / timeDifference} hz`);

    requestAnimationFrame(frame);
}

frame();