namespace Dino.Plugins.Fdp {

public class Plugin : RootInterface, Object {

    public Dino.Application app;

    public void registered(Dino.Application app) {
        this.app = app;
        // TODO: Register FDP form discovery and publishing functionality
    }

    public void shutdown() {
        // TODO: Cleanup resources
    }
}

}
