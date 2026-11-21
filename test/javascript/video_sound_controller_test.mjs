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
  play() { if (this.error) return Promise.reject(this.error); this.paused = false; this.ended = false; this.plays++; this.dispatchEvent(new Event("play")); this.dispatchEvent(new Event("playing")); return Promise.resolve() }
  pause() { this.paused = true; this.dispatchEvent(new Event("pause")) }
  load() { this.loads++; this.ended = false; this.error = null }
  finish() { this.paused = true; this.ended = true; this.dispatchEvent(new Event("ended")) }
}
const entries = ["a", "b", "c"].map(src => ({ src: `/${src}.mp4`, poster: `/${src}.jpg`, orientation: src === "b" ? "portrait" : "landscape" }))
const storage = () => { const values = new Map(); return { getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value) } }
const event = () => ({ preventDefault() {}, stopPropagation() {} })
function setup({ playlist = entries, sessionStorage = storage(), reduced = false, saveData = false, matches = true, interlude = false } = {}) {
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
  controller.hasInterludeTarget = interlude
  if (interlude) controller.interludeTarget = new Element()
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

for (const orientation of ["portrait", "landscape"]) {
  test(`${orientation} still images always show details, while playback respects the overlay setting`, () => {
    const entry = { ...entries[0], orientation, title: "Artist", date: "09.11.2026", overlay: false }
    const { controller, video, visible } = setup({ playlist: [entry], reduced: true })
    visible()
    assert.equal(video.src, null)
    assert.equal(controller.copyTarget.hidden, false)
    controller.togglePlayback(event())
    assert.equal(controller.copyTarget.hidden, true)
    controller.togglePlayback(event())
    assert.equal(controller.copyTarget.hidden, false)
    controller.togglePlayback(event())
    assert.equal(controller.copyTarget.hidden, true)
    video.finish()
    assert.equal(controller.copyTarget.hidden, false)
    visible(false)
    assert.equal(controller.copyTarget.hidden, false)
    controller.disconnect()
  })
}

test("details stay visible while playback is pending or blocked", async () => {
  const { controller, video, visible } = setup({ playlist: [{ ...entries[0], title: "Artist", overlay: false }] })
  let rejectPlayback
  video.play = () => {
    video.paused = false
    video.dispatchEvent(new Event("play"))
    return new Promise((_resolve, reject) => { rejectPlayback = reject })
  }
  visible()
  assert.equal(controller.copyTarget.hidden, false)
  rejectPlayback(new Error("autoplay blocked"))
  await Promise.resolve()
  assert.equal(controller.copyTarget.hidden, false)
  controller.disconnect()
})

test("a silent two-second interlude blocks event details before selecting the next clip", t => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] })
  const saved = storage()
  const { controller, video, visible } = setup({ interlude: true, sessionStorage: saved,
    playlist: entries.map(entry => ({ ...entry, title: "Artist", overlay: true, href: "/event", adminHref: "/admin/event" })) })
  visible(); controller.toggle(event())
  const first = video.src, state = saved.getItem("test-playlist")
  video.finish()
  assert.equal(controller.element.dataset.videoInterlude, "active")
  assert.equal(video.paused, true)
  assert.equal(controller.linkTarget.inert, true)
  assert.equal(controller.copyTarget.hidden, true)
  assert.equal(controller.adminLinkTarget.hidden, true)
  assert.equal(controller.playbackButtonTarget.getAttribute("aria-label"), "Video pausieren")
  t.mock.timers.tick(1999)
  assert.equal(saved.getItem("test-playlist"), state)
  t.mock.timers.tick(1)
  assert.notEqual(video.src, first)
  assert.equal(video.muted, false)
  assert.equal(controller.element.dataset.videoInterlude, "")
  assert.equal(controller.linkTarget.inert, false)
  assert.equal(controller.copyTarget.hidden, false)
  assert.equal(controller.adminLinkTarget.hidden, false)
  controller.disconnect()
})

test("the playback button pauses and resumes the remaining interlude duration", t => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] })
  const { controller, video, visible } = setup({ interlude: true })
  visible(); video.finish()
  const plays = video.plays
  t.mock.timers.tick(700)
  controller.togglePlayback(event())
  assert.equal(controller.interludeTarget.dataset.paused, "true")
  assert.equal(controller.playbackButtonTarget.getAttribute("aria-label"), "Video abspielen")
  t.mock.timers.tick(5000)
  assert.equal(video.plays, plays)
  controller.togglePlayback(event())
  assert.equal(controller.interludeTarget.dataset.paused, "false")
  t.mock.timers.tick(1299)
  assert.equal(video.plays, plays)
  t.mock.timers.tick(1)
  assert.equal(video.plays, plays + 1)
  controller.disconnect()
})

for (const reason of ["offscreen", "tab", "viewport", "reduced", "saveData"]) {
  test(`interlude suspends without consuming a clip when ${reason} makes playback ineligible`, t => {
    t.mock.timers.enable({ apis: ["setTimeout", "Date"] })
    const saved = storage()
    const { controller, video, visible, media, motion } = setup({ interlude: true, sessionStorage: saved })
    const suspend = value => {
      if (reason === "offscreen") visible(!value)
      if (reason === "tab") { document.hidden = value; document.dispatchEvent(new Event("visibilitychange")) }
      if (reason === "viewport") { media.matches = !value; media.dispatchEvent(new Event("change")) }
      if (reason === "reduced") { motion.matches = value; motion.dispatchEvent(new Event("change")) }
      if (reason === "saveData") { navigator.connection.saveData = value; navigator.connection.dispatchEvent(new Event("change")) }
    }
    visible(); video.finish()
    const state = saved.getItem("test-playlist"), plays = video.plays
    t.mock.timers.tick(600); suspend(true)
    assert.equal(controller.interludeTarget.dataset.paused, "true")
    assert.equal(video.src, null)
    t.mock.timers.tick(5000)
    assert.equal(saved.getItem("test-playlist"), state)
    assert.equal(video.plays, plays)
    suspend(false); t.mock.timers.tick(1399)
    assert.equal(saved.getItem("test-playlist"), state)
    t.mock.timers.tick(1)
    assert.equal(video.plays, plays + 1)
    controller.disconnect()
  })
}

test("the interlude covers the next poster until playback really starts and blocked play can resume", async t => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] })
  const { controller, video, visible } = setup({ interlude: true })
  visible(); video.finish()
  const normalPlay = video.play.bind(video)
  video.play = () => { video.paused = true; return Promise.reject(new Error("autoplay blocked")) }
  t.mock.timers.tick(2000)
  await Promise.resolve()
  assert.equal(controller.element.dataset.videoInterlude, "active")
  assert.equal(controller.playbackButtonTarget.getAttribute("aria-label"), "Video abspielen")
  const next = video.src
  video.play = normalPlay
  controller.togglePlayback(event())
  assert.equal(video.src, next)
  assert.equal(controller.element.dataset.videoInterlude, "")
  controller.disconnect()
})

test("explicit play resumes an interlude suspended by reduced motion or save-data", t => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] })
  for (const preference of ["reduced", "saveData"]) {
    const { controller, video, visible, motion } = setup({ interlude: true })
    visible(); video.finish(); t.mock.timers.tick(500)
    if (preference === "reduced") { motion.matches = true; motion.dispatchEvent(new Event("change")) }
    else { navigator.connection.saveData = true; navigator.connection.dispatchEvent(new Event("change")) }
    const plays = video.plays
    controller.togglePlayback(event())
    t.mock.timers.tick(1500)
    assert.equal(video.plays, plays + 1)
    assert.equal(controller.element.dataset.videoInterlude, "")
    controller.disconnect()
  }
})

test("the interlude stays visible during loading and freezes when the pending clip goes offscreen", t => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] })
  const { controller, video, visible } = setup({ interlude: true })
  visible(); video.finish()
  video.play = () => { video.paused = false; video.dispatchEvent(new Event("play")); return Promise.resolve() }
  t.mock.timers.tick(2000)
  const next = video.src
  assert.equal(controller.element.dataset.videoInterlude, "active")
  visible(false)
  assert.equal(controller.interludeTarget.dataset.paused, "true")
  visible()
  assert.equal(video.src, next)
  assert.equal(controller.element.dataset.videoInterlude, "active")
  video.dispatchEvent(new Event("playing"))
  assert.equal(controller.element.dataset.videoInterlude, "")
  controller.disconnect()
})

test("terminal media errors restore the event card and explicit retry reloads the same clip", async t => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] })
  const saved = storage()
  const { controller, video, visible } = setup({ interlude: true, sessionStorage: saved,
    playlist: entries.map(entry => ({ ...entry, title: "Artist", href: "/event", adminHref: "/admin/event" })) })
  visible(); video.finish()
  const normalPlay = video.play.bind(video)
  video.play = () => { video.paused = false; return Promise.resolve() }
  t.mock.timers.tick(2000)
  const next = video.src, state = saved.getItem("test-playlist")
  video.error = new Error("media source failed")
  video.paused = false
  video.dispatchEvent(new Event("error"))
  assert.equal(controller.element.dataset.videoInterlude, "")
  assert.equal(controller.linkTarget.inert, false)
  assert.equal(controller.copyTarget.hidden, false)
  assert.equal(controller.adminLinkTarget.hidden, false)
  assert.equal(controller.playbackButtonTarget.getAttribute("aria-label"), "Video abspielen")
  video.play = normalPlay
  controller.togglePlayback(event())
  await Promise.resolve()
  assert.equal(video.paused, false)
  assert.equal(video.error, null)
  assert.equal(video.src, next)
  assert.equal(saved.getItem("test-playlist"), state)
  assert.equal(controller.element.dataset.videoInterlude, "")
  controller.disconnect()
})

test("cache unload and disconnect cancel the interlude timer", t => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] })
  for (const stop of [controller => document.dispatchEvent(new Event("turbo:before-cache")), controller => controller.disconnect()]) {
    const saved = storage()
    const { controller, video, visible } = setup({ interlude: true, sessionStorage: saved })
    visible(); video.finish()
    const state = saved.getItem("test-playlist"), plays = video.plays
    stop(controller); t.mock.timers.tick(5000)
    assert.equal(video.src, null)
    assert.equal(video.plays, plays)
    assert.equal(saved.getItem("test-playlist"), state)
    controller.disconnect()
  }
})

test("an available interlude does not change single-clip or legacy playback", t => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] })
  for (const playlist of [[entries[0]], []]) {
    const { controller, video, visible } = setup({ playlist, interlude: true })
    if (!playlist.length) video.dataset.videoSoundSrcValue = "/legacy.mp4"
    visible(); video.finish()
    const plays = video.plays
    assert.notEqual(controller.element.dataset.videoInterlude, "active")
    t.mock.timers.tick(5000)
    assert.equal(video.plays, plays)
    assert.equal(video.loop, playlist.length === 0)
    controller.disconnect()
  }
})
