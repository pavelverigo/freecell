const canvas = document.getElementById("canvas");

const width = canvas.width;
const height = canvas.height;

const win_audio = new Audio("audio/Victory SoundFX5.wav");
const card_audio = new Audio("audio/cardSlide1.wav");
card_audio.playbackRate = 1.5;

const ctx = canvas.getContext("2d");

function string_from_ptr_len(ptr, len) {
    const slice = new Uint8Array(wasm_exports.memory.buffer, ptr, len);
    return new TextDecoder().decode(slice);
}

const wasm = await WebAssembly.instantiateStreaming(fetch("freecell.wasm"), {
    env: {
        js__output_image_data: (ptr, len) => {
            let data_slice = new Uint8ClampedArray(wasm_exports.memory.buffer, ptr, 4 * len);
            let image_data = new ImageData(data_slice, width, height);
            ctx.putImageData(image_data, 0, 0);
        },

        js__play_sound: (ptr, len) => {
            const name = string_from_ptr_len(ptr, len);
            if (name === "win") win_audio.play();
            if (name === "card") card_audio.play();
        },

        js__get_timestamp: () => performance.now(),

        js__get_random_u32: () => Math.floor(Math.random() * 0xFFFFFFFF),

        js__output_line_to_console: (ptr, len) => console.log(string_from_ptr_len(ptr, len)),
    },
});
const wasm_exports = wasm.instance.exports;

wasm_exports.wasm__init(width, height);

const wasm__frame                     = wasm_exports.wasm__frame;
const wasm__update_mouse_inside       = wasm_exports.wasm__update_mouse_inside;
const wasm__update_mouse_position     = wasm_exports.wasm__update_mouse_position;
const wasm__update_mouse_button_state = wasm_exports.wasm__update_mouse_button_state;

canvas.addEventListener("mouseover", (e) => {
    wasm__update_mouse_inside(true);
    // sync all mouse state on entrance, other listeners will sync their respective state going forward
    wasm__update_mouse_position(e.offsetX, e.offsetY);
    wasm__update_mouse_button_state(0, (e.buttons & 1) !== 0);
    wasm__update_mouse_button_state(1, (e.buttons & 2) !== 0);
    wasm__update_mouse_button_state(2, (e.buttons & 4) !== 0);
});

canvas.addEventListener("mouseout", (e) => {
    wasm__update_mouse_inside(false);
});

canvas.addEventListener("mousemove", (e) => {
    wasm__update_mouse_position(e.offsetX, e.offsetY);
});

canvas.addEventListener("mouseup", (e) => {
    if (e.button === 0 || e.button === 1 || e.button === 2) {
        wasm__update_mouse_button_state(e.button, false);
    }
});

canvas.addEventListener("mousedown", (e) => {
    e.preventDefault();
    if (e.button === 0 || e.button === 1 || e.button === 2) {
        wasm__update_mouse_button_state(e.button, true);
    }
});

canvas.addEventListener("contextmenu", (e) => {
    e.preventDefault();
});

function frame() {
    wasm__frame();
    requestAnimationFrame(frame);
}

frame();