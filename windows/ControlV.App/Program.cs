using Velopack;

namespace ControlV.App;

public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        // Must run first: handles install/uninstall/update hooks and exits when
        // launched by the installer with a hook argument.
        VelopackApp.Build().Run();

        var app = new App();
        app.InitializeComponent();
        app.Run();
    }
}
