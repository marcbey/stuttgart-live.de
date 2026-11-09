import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const source = (await readFile(new URL("../../app/javascript/controllers/video_sound_controller.js", import.meta.url), "utf8"))
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
const { default: VideoSoundController } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

class Element extends EventTarget {
  constructor() { super(); this.dataset = {}; this.attributes = new Map(); this.hidden = false; this.textContent = "old"; this.classList = { toggle() {} } }
  setAttribute(key, value) { this.attributes.set(key, String(value)) }
  getAttribute(key) { return this.attributes.get(key) ?? null }
  hasAttribute(key) { return this.attributes.has(key) }
  removeAttribute(key) { this.attributes.delete(key) }
}
class Video extends Element {
  constructor() { super(); this.paused = true; this.muted = true; this.volume = 1; this.loop = true; this.plays = 0; this.loads = 0; this.ended = false }
  get src() { return this.getAttribute("src") }
  set src(value) { this.setAttribute("src", value); this.ended = false }
  play() { this.paused = false; this.ended = false; this.plays++; this.dispatchEvent(new Event("play")); return Promise.resolve() }
  pause() { this.paused = true; this.dispatchEvent(new Event("pause")) }
  load() { this.loads++; this.ended = false }
  finish() { this.paused = true; this.ended = true; this.dispatchEvent(new Event("ended")) }
}
const entries = ["a", "b", "c"].map(src => ({ src: `/${src}.mp4`, poster: `/${src}.jpg`, orientation: src === "b" ? "portrait" : "landscape" }))
const storage = () => { const values = new Map(); return { getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value) } }
const event = () => ({ preventDefault() {}, stopPropagation() {} })
function setup({ playlist = entries, sessionStorage = storage(), reduced = false, saveData = false, matches = true } = {}) {
  const media = Object.assign(new EventTarget(), { matches })
  const motion = Object.assign(new EventTarget(), { matches: reduced })
  globalThis.window = { sessionStorage, matchMedia: query => query.includes("reduced-motion") ? motion : media }
  globalThis.document = Object.assign(new EventTarget(), { hidden: false })
  Object.defineProperty(globalThis, "navigator", { configurable: true, value: { connection: Object.assign(new EventTarget(), { saveData }) } })
  globalThis.IntersectionObserver = class {
    constructor(callback) { this.callback = callback }
    observe() {}
    disconnect() { this.disconnected = true }
  }
  const controller = Object.assign(new VideoSoundController(), { element: new Element(), videoTarget: new Video(), hasVideoTarget: true,
    playlistValue: playlist, storageKeyValue: "test-playlist", mediaValue: "(min-width: 768px)" })
  for (const name of ["button", "playbackButton", "link", "copy", "title", "subtitle", "date", "location", "adminLink"]) {
    controller[`${name}Target`] = new Element()
    controller[`has${name[0].toUpperCase()}${name.slice(1)}Target`] = true
  }
  controller.connect()
  const visible = (value = true) => controller.visibilityObserver.callback([{ isIntersecting: value, intersectionRect: { width: value ? 500 : 0, height: value ? 300 : 0 } }])
  return { controller, video: controller.videoTarget, media, motion, visible }
}

test("playlist plays complete random rounds without duplicates or adjacent repeats", () => {
  const { controller, video, visible } = setup({ playlist: [...entries, entries[0]] })
  visible()
  assert.equal(video.loop, false)
  const played = []
  for (let index = 0; index < 30; index++) { played.push(video.src); video.finish() }
  for (let index = 0; index < played.length; index += 3) assert.equal(new Set(played.slice(index, index + 3)).size, 3)
  for (let index = 1; index < played.length; index++) assert.notEqual(played[index], played[index - 1])
  controller.disconnect()
})

test("hidden and ineligible players do not select, load or consume persisted clips", () => {
  const saved = storage()
  const { controller, video, visible, media } = setup({ sessionStorage: saved, matches: false })
  visible()
  assert.equal(video.src, null)
  assert.equal(saved.getItem("test-playlist"), null)
  media.matches = true; media.dispatchEvent(new Event("change"))
  assert.ok(video.src)
  const previous = video.src, state = saved.getItem("test-playlist")
  visible(false)
  assert.equal(video.src, null)
  video.finish()
  assert.equal(video.src, null)
  assert.equal(saved.getItem("test-playlist"), state)
  visible()
  assert.notEqual(video.src, previous)
  controller.disconnect()
})

test("session reload continues the unplayed round", () => {
  const saved = storage(), played = []
  for (let index = 0; index < 3; index++) {
    const { controller, video, visible } = setup({ sessionStorage: saved })
    visible(); played.push(video.src); controller.disconnect()
  }
  assert.equal(new Set(played).size, 3)
})

test("unavailable, corrupt and outdated session state still plays only current entries", () => {
  for (const sessionStorage of [
    { getItem() { throw Error("blocked") }, setItem() { throw Error("blocked") } },
    { getItem: () => "broken", setItem() {} },
    { getItem: () => JSON.stringify({ signature: JSON.stringify(entries.map(entry => entry.src).sort()), remaining: [entries[0].src], last: entries[0].src }), setItem() {} },
    { getItem: () => JSON.stringify({ remaining: ["/deleted.mp4"], last: "/deleted.mp4" }), setItem() {} }
  ]) {
    const { controller, video, visible } = setup({ sessionStorage })
    visible()
    assert.ok(entries.some(entry => entry.src === video.src))
    video.finish()
    assert.ok(entries.some(entry => entry.src === video.src))
    controller.disconnect()
  }
})

test("clip switches update safe text, links, poster and orientation and clear absent metadata", () => {
  const rich = { src: "/rich.mp4", poster: "/rich.jpg", href: "/events/rich", label: "Details", title: "<b>Title</b>", subtitle: "Subtitle", date: "Tomorrow", location: "Venue", overlay: true, adminHref: "/admin/rich", orientation: "portrait" }
  const empty = { src: "/empty.mp4", orientation: "landscape" }
  const { controller, video, visible } = setup({ playlist: [rich, empty] })
  visible()
  if (video.src !== rich.src) video.finish()
  assert.equal(controller.titleTarget.textContent, rich.title)
  assert.equal(controller.copyTarget.hidden, false)
  assert.equal(controller.linkTarget.getAttribute("href"), rich.href)
  assert.equal(controller.linkTarget.getAttribute("aria-label"), rich.label)
  assert.equal(controller.adminLinkTarget.getAttribute("href"), rich.adminHref)
  assert.equal(video.getAttribute("poster"), rich.poster)
  assert.equal(controller.element.dataset.videoOrientation, "portrait")
  video.finish()
  assert.equal(video.src, empty.src)
  assert.equal(controller.titleTarget.textContent, "")
  assert.equal(controller.titleTarget.hidden, true)
  assert.equal(controller.copyTarget.hidden, true)
  assert.equal(controller.linkTarget.hasAttribute("href"), false)
  assert.equal(controller.linkTarget.hasAttribute("aria-label"), false)
  assert.equal(controller.adminLinkTarget.hidden, true)
  assert.equal(video.hasAttribute("poster"), false)
  assert.equal(controller.element.dataset.videoOrientation, "landscape")
  controller.disconnect()
})

test("pause and mute preferences survive visibility changes and clip transitions", () => {
  const { controller, video, visible } = setup()
  visible(); controller.toggle(event())
  assert.equal(video.muted, false)
  const first = video.src
  controller.togglePlayback(event()); visible(false); visible()
  assert.equal(video.paused, true)
  controller.togglePlayback(event())
  assert.equal(video.src, first)
  video.finish()
  assert.notEqual(video.src, first)
  assert.equal(video.muted, false)
  controller.disconnect()
})

test("reduced motion and save-data require explicit playback", () => {
  for (const settings of [{ reduced: true }, { saveData: true }]) {
    const { controller, video, visible } = setup(settings)
    visible()
    assert.equal(video.src, null)
    controller.togglePlayback(event())
    assert.ok(video.src)
    video.finish()
    assert.equal(video.paused, false)
    controller.disconnect()
  }
})

test("one unique clip ends without looping and replays only on explicit play", () => {
  const { controller, video, visible } = setup({ playlist: [entries[0], entries[0]] })
  visible(); video.finish()
  const plays = video.plays
  controller.updatePlayback(); visible(false); visible()
  assert.equal(video.plays, plays)
  assert.equal(video.paused, true)
  controller.togglePlayback(event())
  assert.equal(video.plays, plays + 1)
  controller.disconnect()
})

test("disconnect removes ended handling and unloads the source", () => {
  const saved = storage()
  const { controller, video, visible } = setup({ sessionStorage: saved })
  visible(); controller.disconnect()
  const state = saved.getItem("test-playlist"), plays = video.plays
  video.finish()
  assert.equal(saved.getItem("test-playlist"), state)
  assert.equal(video.plays, plays)
  assert.equal(video.src, null)
})

test("existing non-playlist players keep their lazy source and loop behavior", () => {
  const { controller, video, visible } = setup({ playlist: [] })
  video.dataset.videoSoundSrcValue = "/legacy.mp4"
  visible()
  assert.equal(video.src, "/legacy.mp4")
  assert.equal(video.loop, true)
  visible(false)
  assert.equal(video.src, null)
  controller.disconnect()
})

test("an aborted play from an unloaded clip cannot mute the next clip", async () => {
  const { controller, video, visible } = setup()
  let rejectPlayback
  video.play = () => { video.paused = false; return new Promise((_resolve, reject) => { rejectPlayback = reject }) }
  visible(); controller.toggle(event())
  const rejectPrevious = rejectPlayback
  video.finish()
  rejectPrevious(new Error("play aborted by source change"))
  await Promise.resolve()
  assert.equal(video.muted, false)
  controller.disconnect()
})
