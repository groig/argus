import {mkdir, readFile, writeFile} from "node:fs/promises"
import path from "node:path"
import {setTimeout as sleep} from "node:timers/promises"
import {spawn} from "node:child_process"

const baseUrl = process.env.ARGUS_SCREENSHOT_BASE_URL || "http://127.0.0.1:4101"
const manifestPath =
  process.env.ARGUS_SCREENSHOT_MANIFEST_PATH || "/tmp/argus-screenshot-manifest.json"
const outputDir =
  process.env.ARGUS_SCREENSHOT_OUTPUT_DIR ||
  path.resolve(process.cwd(), "docs/screenshots")
const webdriverPort = Number(process.env.ARGUS_SCREENSHOT_WEBDRIVER_PORT || "9515")
const webdriverUrl = `http://127.0.0.1:${webdriverPort}`
const chromiumPath = process.env.CHROMIUM_PATH || "/usr/bin/chromium"
const elementKey = "element-6066-11e4-a52e-4f735466cecf"

async function request(method, pathname, body) {
  const response = await fetch(`${webdriverUrl}${pathname}`, {
    method,
    headers: {"content-type": "application/json"},
    body: body === undefined ? undefined : JSON.stringify(body),
  })

  let payload = {}

  if (response.status !== 204) {
    payload = await response.json()
  }

  if (!response.ok) {
    const message = payload.value?.message || response.statusText
    throw new Error(`${method} ${pathname} failed: ${message}`)
  }

  return payload
}

async function waitFor(fn, {timeoutMs = 15_000, intervalMs = 150} = {}) {
  const startedAt = Date.now()

  while (Date.now() - startedAt < timeoutMs) {
    try {
      const result = await fn()

      if (result) {
        return result
      }
    } catch (_error) {
      // Wait and retry until the timeout expires.
    }

    await sleep(intervalMs)
  }

  throw new Error(`Timed out after ${timeoutMs}ms`)
}

function spawnChromedriver() {
  const child = spawn(
    "chromedriver",
    [`--port=${webdriverPort}`, "--allowed-ips=127.0.0.1"],
    {
      stdio: "inherit",
    },
  )

  return child
}

async function createSession() {
  const response = await request("POST", "/session", {
    capabilities: {
      alwaysMatch: {
        browserName: "chrome",
        "goog:chromeOptions": {
          binary: chromiumPath,
          args: [
            "--headless=new",
            "--disable-gpu",
            "--disable-dev-shm-usage",
            "--hide-scrollbars",
            "--no-sandbox",
            "--window-size=1600,1200",
          ],
        },
      },
    },
  })

  return response.sessionId || response.value?.sessionId
}

async function deleteSession(sessionId) {
  await request("DELETE", `/session/${sessionId}`)
}

async function navigate(sessionId, pathname) {
  await request("POST", `/session/${sessionId}/url`, {
    url: new URL(pathname, baseUrl).toString(),
  })
}

async function setWindowRect(sessionId, {width, height}) {
  await request("POST", `/session/${sessionId}/window/rect`, {
    width,
    height,
  })
}

async function execute(sessionId, script, args = []) {
  const response = await request("POST", `/session/${sessionId}/execute/sync`, {
    script,
    args,
  })

  return response.value
}

async function findElement(sessionId, selector) {
  const response = await request("POST", `/session/${sessionId}/element`, {
    using: "css selector",
    value: selector,
  })

  const element = response.value
  const id = element?.[elementKey]

  if (!id) {
    throw new Error(`Element not found for selector: ${selector}`)
  }

  return id
}

async function clearElement(sessionId, elementId) {
  await request("POST", `/session/${sessionId}/element/${elementId}/clear`, {})
}

async function sendKeys(sessionId, elementId, value) {
  await request("POST", `/session/${sessionId}/element/${elementId}/value`, {
    text: value,
    value: [...value],
  })
}

async function click(sessionId, elementId) {
  await request("POST", `/session/${sessionId}/element/${elementId}/click`, {})
}

async function waitForSelector(sessionId, selector, timeoutMs = 15_000) {
  return waitFor(() => findElement(sessionId, selector), {timeoutMs})
}

async function waitForPath(sessionId, pathname, timeoutMs = 15_000) {
  await waitFor(
    async () => {
      const currentUrl = await execute(sessionId, "return window.location.href")
      return new URL(currentUrl).pathname === pathname
    },
    {timeoutMs},
  )
}

async function resizeForPage(sessionId, minHeight = 1100) {
  const height = await execute(
    sessionId,
    `
      return Math.max(
        document.body.scrollHeight,
        document.documentElement.scrollHeight,
        document.body.offsetHeight,
        document.documentElement.offsetHeight
      )
    `,
  )

  await setWindowRect(sessionId, {
    width: 1600,
    height: Math.max(minHeight, Math.min(Number(height) + 120, 2200)),
  })
}

async function writeScreenshot(sessionId, filename) {
  const response = await request("GET", `/session/${sessionId}/screenshot`)
  const image = Buffer.from(response.value, "base64")
  await writeFile(path.join(outputDir, filename), image)
}

async function capturePage(sessionId, pathname, selector, filename, minHeight) {
  await navigate(sessionId, pathname)
  await waitForSelector(sessionId, selector)
  await execute(
    sessionId,
    "return window.liveSocket && window.liveSocket.isConnected ? window.liveSocket.isConnected() : true",
  )
  await sleep(250)
  await resizeForPage(sessionId, minHeight)
  await sleep(150)
  await writeScreenshot(sessionId, filename)
}

async function login(sessionId, manifest) {
  await navigate(sessionId, "/login")
  await waitForSelector(sessionId, "#login-form")

  const email = await findElement(sessionId, "#login-form input[name='user[email]']")
  const password = await findElement(sessionId, "#login-form input[name='user[password]']")
  const submit = await findElement(sessionId, "#login-form button")

  await clearElement(sessionId, email)
  await sendKeys(sessionId, email, manifest.login.email)
  await clearElement(sessionId, password)
  await sendKeys(sessionId, password, manifest.login.password)
  await click(sessionId, submit)

  await waitForPath(sessionId, "/projects")
  await waitForSelector(sessionId, "[id^='project-card-']")
}

async function main() {
  await mkdir(outputDir, {recursive: true})

  const manifest = JSON.parse(await readFile(manifestPath, "utf8"))
  const chromedriver = spawnChromedriver()

  try {
    await waitFor(async () => {
      const response = await fetch(`${webdriverUrl}/status`)
      return response.ok
    })

    const sessionId = await createSession()

    try {
      await login(sessionId, manifest)

      await capturePage(
        sessionId,
        manifest.routes.dashboard,
        "[id^='project-card-']",
        "dashboard.png",
        1400,
      )

      await capturePage(
        sessionId,
        manifest.routes.issue_detail,
        "#issue-selected-event",
        "issue-detail.png",
        1700,
      )

      await capturePage(
        sessionId,
        manifest.routes.log_detail,
        "#log-summary-panel",
        "log-detail.png",
        1400,
      )
    } finally {
      await deleteSession(sessionId)
    }
  } finally {
    chromedriver.kill("SIGTERM")
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
