(function () {
    var form = document.getElementById("chatForm");
    var input = document.getElementById("chatInput");
    var messages = document.getElementById("chatMessages");
    var sendBtn = document.getElementById("sendBtn");
    var history = [];

    function addMessage(role, text) {
        var wrapper = document.createElement("div");
        wrapper.className = "message " + role;
        var bubble = document.createElement("div");
        bubble.className = "bubble";
        bubble.textContent = text;
        wrapper.appendChild(bubble);
        messages.appendChild(wrapper);
        messages.scrollTop = messages.scrollHeight;
    }

    form.addEventListener("submit", function (e) {
        e.preventDefault();
        var text = input.value.trim();
        if (!text) return;

        addMessage("user", text);
        history.push({ role: "user", content: text });
        input.value = "";
        sendBtn.disabled = true;

        fetch("/api/chat", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ messages: history }),
        })
            .then(function (res) { return res.json(); })
            .then(function (data) {
                var reply = data.response || data.error || "No response";
                addMessage("assistant", reply);
                history.push({ role: "assistant", content: reply });
            })
            .catch(function () {
                addMessage("assistant", "Error: could not reach the server.");
            })
            .finally(function () {
                sendBtn.disabled = false;
                input.focus();
            });
    });
})();
