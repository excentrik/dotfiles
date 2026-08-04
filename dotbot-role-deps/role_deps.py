import dotbot


class RoleDeps(dotbot.Plugin):
    supports_dry_run = True
    _dependsDirective = "depends"

    def can_handle(self, directive):
        return directive == self._dependsDirective

    def handle(self, directive, data):
        if directive != self._dependsDirective:
            raise ValueError(f"RoleDeps cannot handle directive {directive}")
        if not isinstance(data, list) or not all(isinstance(item, str) for item in data):
            raise ValueError("depends directive must be a list of role names")
        self._log.info("Role dependencies are resolved before Dotbot runs")
        return True
