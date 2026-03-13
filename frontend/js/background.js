(function () {
    const bg = document.getElementById("bg");
    if (!bg) return;

    // Main canvas (cyan orbs)
    var canvas = document.createElement("canvas");
    canvas.style.cssText = "position:fixed;inset:0;z-index:0;pointer-events:none";
    bg.appendChild(canvas);
    var ctx = canvas.getContext("2d");

    // Overlay canvas inside chat container (darker purple orbs)
    var chatBox = document.querySelector(".chat-container");
    var overlay = document.createElement("canvas");
    overlay.style.cssText = "position:absolute;inset:0;z-index:0;pointer-events:none;border-radius:16px";
    chatBox.style.position = "relative";
    chatBox.insertBefore(overlay, chatBox.firstChild);
    var ctx2 = overlay.getContext("2d");

    function resize() {
        canvas.width = window.innerWidth;
        canvas.height = window.innerHeight;
        overlay.width = chatBox.offsetWidth;
        overlay.height = chatBox.offsetHeight;
    }
    resize();
    window.addEventListener("resize", resize);

    var mouseX = -1000, mouseY = -1000;
    document.addEventListener("mousemove", function (e) {
        mouseX = e.clientX;
        mouseY = e.clientY;
    });

    var orbs = [];
    for (var i = 0; i < 15; i++) {
        orbs.push({
            x: Math.random() * window.innerWidth,
            y: Math.random() * window.innerHeight,
            r: 60 + Math.random() * 120,
            dx: (Math.random() - 0.5) * 3,
            dy: (Math.random() - 0.5) * 2.4,
            alpha: 0.27 + Math.random() * 0.36
        });
    }

    function drawOrb(c, ox, oy, o, hue, alphaScale, sat) {
        var a = o.alpha * alphaScale;
        var s = sat !== undefined ? sat : 70;
        var grad = c.createRadialGradient(ox, oy, 0, ox, oy, o.r);
        grad.addColorStop(0, "hsla(" + hue + "," + s + "%,60%," + a + ")");
        grad.addColorStop(1, "hsla(" + hue + "," + s + "%,60%,0)");
        c.beginPath();
        c.arc(ox, oy, o.r, 0, Math.PI * 2);
        c.fillStyle = grad;
        c.fill();
    }

    function animate() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx2.clearRect(0, 0, overlay.width, overlay.height);

        var rect = chatBox.getBoundingClientRect();

        for (var i = 0; i < orbs.length; i++) {
            var o = orbs[i];

            // Mouse repulsion
            var distX = o.x - mouseX;
            var distY = o.y - mouseY;
            var dist = Math.sqrt(distX * distX + distY * distY);
            var pushRadius = 150;
            if (dist < pushRadius && dist > 0) {
                var force = (1 - dist / pushRadius) * 2;
                o.dx += (distX / dist) * force;
                o.dy += (distY / dist) * force;
            }

            // Dampen velocity so orbs don't fly off
            o.dx *= 0.98;
            o.dy *= 0.98;

            // Maintain minimum drift speed
            var speed = Math.sqrt(o.dx * o.dx + o.dy * o.dy);
            if (speed < 0.3) {
                o.dx += (Math.random() - 0.5) * 0.2;
                o.dy += (Math.random() - 0.5) * 0.2;
            }

            o.x += o.dx;
            o.y += o.dy;
            if (o.x < -o.r) o.x = canvas.width + o.r;
            if (o.x > canvas.width + o.r) o.x = -o.r;
            if (o.y < -o.r) o.y = canvas.height + o.r;
            if (o.y > canvas.height + o.r) o.y = -o.r;

            // Cyan on main canvas
            drawOrb(ctx, o.x, o.y, o, 200, 1);

            // Darker purple on overlay
            drawOrb(ctx2, o.x - rect.left, o.y - rect.top, o, 0, 0.3, 0);
        }
        requestAnimationFrame(animate);
    }
    animate();
})();
