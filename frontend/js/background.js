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
})();
