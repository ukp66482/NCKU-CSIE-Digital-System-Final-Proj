# Configurable 3×3 Convolution IP (Without AXI-Lite)

This section focuses on building a working 3×3 convolution hardware module.
The goal is to implement the convolution datapath and verify functionality through `functional simulation`.

In the next section, you will extend this design by wrapping the 3×3 kernel coefficients with an AXI-Lite slave interface to enable software-configurable filtering.