{{flutter_js}}
{{flutter_build_config}}

const loaderStyle = document.createElement('style');
loaderStyle.innerHTML = `
  body {
    background: #ffffff;
    margin: 0;
    height: 100vh;
    display: flex;
    justify-content: center;
    align-items: center;
    flex-direction: column;
    overflow: hidden;
    font-family: 'Plus Jakarta Sans', sans-serif;
  }
  .app-logo {
    width: 100px;
    height: 100px;
    margin-bottom: 24px;
    border-radius: 50%;
  }
  .loading-text {
    color: #64748b;
    font-size: 1.1rem;
    font-weight: 500;
    margin-bottom: 40px;
  }
  .spinner {
    width: 32px;
    height: 32px;
    border: 3px solid transparent;
    border-top-color: #007CFF;
    border-radius: 50%;
    animation: spin 1s linear infinite;
  }
  @keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
  }
`;
document.head.appendChild(loaderStyle);

const loaderContainer = document.createElement('div');
loaderContainer.id = "app-loader";
loaderContainer.innerHTML = `
  <img src="icons/Icon-192.png" alt="Yatri Billing Logo" class="app-logo">
  <div class="loading-text">Initializing Yatri Billing...</div>
  <div class="spinner"></div>
`;
// Ensure the container itself uses flex to center everything vertically
loaderContainer.style.display = 'flex';
loaderContainer.style.flexDirection = 'column';
loaderContainer.style.alignItems = 'center';

document.body.appendChild(loaderContainer);

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(function(registrations) {
    for (let registration of registrations) {
      registration.unregister();
    }
  });
}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: null,
  },
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    
    loaderContainer.style.transition = 'opacity 0.3s ease';
    loaderContainer.style.opacity = '0';
    
    setTimeout(async () => {
      loaderContainer.remove();
      document.body.style.background = 'transparent';
      await appRunner.runApp();
    }, 300);
  }
});
