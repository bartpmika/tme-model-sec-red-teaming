(function () {
    var form = document.getElementById("chatForm");
    var input = document.getElementById("chatInput");
    var messages = document.getElementById("chatMessages");
    var sendBtn = document.getElementById("sendBtn");

    function addMessage(role, text) {
        var wrapper = document.createElement("div");
        wrapper.className = "message " + role;
        var bubble = document.createElement("div");
        bubble.className = "bubble";
        bubble.textContent = text;
        wrapper.appendChild(bubble);
        messages.appendChild(wrapper);
        messages.scrollTop = messages.scrollHeight;
        return bubble;
    }

    form.addEventListener("submit", function (e) {
        e.preventDefault();
        var text = input.value.trim();
        if (!text) return;

        addMessage("user", text);
        input.value = "";
        sendBtn.disabled = true;

        var bubble = addMessage("assistant", "");

        fetch("/api/chat", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ message: text }),
        })
            .then(function (res) {
                if (!res.ok) throw new Error("Server error");
                var reader = res.body.getReader();
                var decoder = new TextDecoder();
                var buffer = "";

                function read() {
                    return reader.read().then(function (result) {
                        if (result.done) return;
                        buffer += decoder.decode(result.value, { stream: true });
                        var lines = buffer.split("\n");
                        buffer = lines.pop();
                        for (var i = 0; i < lines.length; i++) {
                            var line = lines[i].trim();
                            if (!line.startsWith("data: ")) continue;
                            var payload = line.substring(6);
                            if (payload === "[DONE]") return;
                            try {
                                var chunk = JSON.parse(payload);
                                if (chunk.error) {
                                    bubble.textContent = chunk.error;
                                    return;
                                }
                                if (chunk.token) {
                                    bubble.textContent += chunk.token;
                                    messages.scrollTop = messages.scrollHeight;
                                }
                            } catch (err) {}
                        }
                        return read();
                    });
                }

                return read();
            })
            .catch(function () {
                if (!bubble.textContent) {
                    bubble.textContent = "Error: could not reach the server.";
                }
            })
            .finally(function () {
                sendBtn.disabled = false;
                input.focus();
            });
    });
})();
