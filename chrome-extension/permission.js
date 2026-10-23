const button = document.querySelector('button');
const done = document.querySelector('.done');

async function allow() {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    stream.getTracks().forEach((track) => track.stop());
    button.hidden = true;
    done.hidden = false;
  } catch {
    button.textContent = 'Try again';
    done.hidden = false;
    done.textContent = 'Chrome blocked it. Click the icon at the right of the address bar to allow the microphone, then try again.';
    done.style.color = '#d70015';
  }
}

button.addEventListener('click', allow);
