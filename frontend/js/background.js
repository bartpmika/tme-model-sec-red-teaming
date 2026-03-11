(function () {
    const bg = document.getElementById("bg");
    if (!bg) return;

    // Only attach mousemove on devices with hover support
    if (!window.matchMedia("(hover: none)").matches) {
        document.addEventListener("mousemove", function (e) {
            const x = ((e.clientX / window.innerWidth) * 100).toFixed(1);
            const y = ((e.clientY / window.innerHeight) * 100).toFixed(1);
            bg.style.background =
                "radial-gradient(circle at " + x + "% " + y + "%, #1a1040, #0d1a3a 40%, #0a0a1a 70%)";
        });
    }

    // Floating orbs
    var canvas = document.createElement("canvas");
    canvas.style.cssText = "position:fixed;inset:0;z-index:0;pointer-events:none";
    bg.appendChild(canvas);
    var ctx = canvas.getContext("2d");

    function resize() {
        canvas.width = window.innerWidth;
        canvas.height = window.innerHeight;
    }
    resize();
    window.addEventListener("resize", resize);

    var orbs = [];
    for (var i = 0; i < 15; i++) {
        orbs.push({
            x: Math.random() * window.innerWidth,
            y: Math.random() * window.innerHeight,
            r: 60 + Math.random() * 120,
            dx: (Math.random() - 0.5) * 3,
            dy: (Math.random() - 0.5) * 2.4,
            hue: Math.random() < 0.5 ? 250 : 200,
            alpha: 0.27 + Math.random() * 0.36
        });
    }

    function animate() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        for (var i = 0; i < orbs.length; i++) {
            var o = orbs[i];
            o.x += o.dx;
            o.y += o.dy;
            if (o.x < -o.r) o.x = canvas.width + o.r;
            if (o.x > canvas.width + o.r) o.x = -o.r;
            if (o.y < -o.r) o.y = canvas.height + o.r;
            if (o.y > canvas.height + o.r) o.y = -o.r;

            var grad = ctx.createRadialGradient(o.x, o.y, 0, o.x, o.y, o.r);
            grad.addColorStop(0, "hsla(" + o.hue + ",70%,60%," + o.alpha + ")");
            grad.addColorStop(1, "hsla(" + o.hue + ",70%,60%,0)");
            ctx.beginPath();
            ctx.arc(o.x, o.y, o.r, 0, Math.PI * 2);
            ctx.fillStyle = grad;
            ctx.fill();
        }
        requestAnimationFrame(animate);
    }
    animate();
})();
