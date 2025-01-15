{
  fetchFromGitHub,
  lib,
  php,
}:

php.buildComposerProject2 (finalAttrs: {
  pname = "speedtest-tracker";
  version = "1.0.1";

  src = fetchFromGitHub {
    owner = "alexjustesen";
    repo = "speedtest-tracker";
    rev = "v${finalAttrs.version}";
    hash = "sha256-aEYRd0BWPp1iBGRri6vqUEt5CO9mZ2CZVMjDItVWEto=";
  };

  vendorHash = "sha256-L8vT4NWFLaIOk36RVFFiwDG9kfyWIyKuWf5ED+1TThA=";

  meta = {
    description = "Speedtest Tracker is a self-hosted application that monitors the performance and uptime of your internet connection";
    homepage = "https://github.com/alexjustesen/speedtest-tracker";
    license = lib.licenses.mit;
    mainProgram = "speedtest-tracker";
    maintainers = lib.teams.php.members;
  };
})