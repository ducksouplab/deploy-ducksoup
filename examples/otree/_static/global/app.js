const init = () => {
    const mountEl = document.getElementById("ducksoup-root");
    const wsProtocol = window.location.protocol === "https:" ? "wss" : "ws";
    const { ducksoupURL } = js_vars;
    const ducksoupPath = ducksoupURL.split("://")[1];

    const embedOptions = {
        mountEl,
        callback: ducksoupListener,
    }
    const peerOptions = {
        signalingUrl: `${wsProtocol}://${ducksoupPath}ws`,
        ...js_vars.peerOptions,
    };

    DuckSoup.render(embedOptions, peerOptions);
};

const hideDuckSoup = () => {
    document.getElementById("stopped").classList.remove("d-none");
    document.getElementById("ducksoup-root").classList.add("d-none");
}

const replaceMessage = (message) => {
    document.getElementById("stopped-message").innerHTML = message;
    hideDuckSoup();
}

// communication with iframe
const ducksoupListener = (message) => {
    const { kind } = message;
    console.log("[DuckSoup event] ", kind)
    if (kind === "end") {
        document.querySelector(".ducksoup-container").classList.add("d-none");
        liveSend({
            kind: "end",
        });
    } else if (kind === "ending") {
        document.querySelector(".ducksoup-container .overlay").classList.remove("d-none");
    } else if (kind === "error-full") {
        replaceMessage("Error: room full");
    } else if (kind === "error-duplicate") {
        replaceMessage("Error: already connected");
    } else if (kind === "disconnection") {
        replaceMessage("Disconnected");
    } else if (kind === "error") {
        replaceMessage("Error");
    }
};

// callback from python
window.liveRecv = (data) => {
    if(data === 'next') {   
        setTimeout(() => {
            document.getElementById("form").submit();
        }, 2000);
    }    
}

document.addEventListener("DOMContentLoaded", init);