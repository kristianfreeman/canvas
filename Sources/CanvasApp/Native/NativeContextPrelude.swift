/// The globals docs/native.md promises the bundle, built on the native
/// functions `NativeContextCore` installs (`__schedule`, `__cancel`,
/// `__now`, `__log`). Swift fires a timer by calling `__fireTimer(id)`.
enum NativeContextPrelude {
    static let source = #"""
    (function (g) {
      var timers = new Map()
      var nextTimer = 1
      var origin = g.__now()

      function report(error) {
        if (g.canvasNative) g.canvasNative.reportError(error)
        else g.__post({ type: 'error', message: String(error && error.message || error) })
      }

      function add(fn, ms, repeats, args) {
        if (typeof fn !== 'function') return 0
        var id = nextTimer++
        timers.set(id, { fn: fn, args: args, repeats: repeats })
        g.__schedule(id, Math.max(0, Number(ms) || 0), repeats)
        return id
      }

      function clear(id) {
        if (timers.delete(id)) g.__cancel(id)
      }

      g.setTimeout = function (fn, ms) { return add(fn, ms, false, [].slice.call(arguments, 2)) }
      g.setInterval = function (fn, ms) { return add(fn, ms, true, [].slice.call(arguments, 2)) }
      g.clearTimeout = clear
      g.clearInterval = clear

      g.__fireTimer = function (id) {
        var timer = timers.get(id)
        if (!timer) return
        if (!timer.repeats) timers.delete(id)
        try { timer.fn.apply(undefined, timer.args) } catch (error) { report(error) }
      }

      g.__resetTimers = function () {
        timers.forEach(function (_, id) { g.__cancel(id) })
        timers.clear()
      }

      if (typeof g.queueMicrotask !== 'function') {
        g.queueMicrotask = function (fn) { Promise.resolve().then(fn).catch(report) }
      }

      g.performance = { timeOrigin: origin, now: function () { return g.__now() - origin } }

      function text(args) {
        return [].map.call(args, function (arg) {
          if (typeof arg === 'string') return arg
          if (arg instanceof Error) return arg.stack ? arg.message + '\n' + arg.stack : arg.message
          try { return JSON.stringify(arg) } catch (error) { return String(arg) }
        }).join(' ')
      }

      g.console = {}
      ;['log', 'info', 'debug', 'warn', 'error'].forEach(function (level) {
        g.console[level] = function () { g.__log(level, text(arguments)) }
      })
    })(globalThis);
    """#
}
