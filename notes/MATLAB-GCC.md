# MATLAB, GCC, `libstdc++`, and `libgfortran` compatibility

Different versions of MATLAB support different versions of GCC when compiling MEX files on Linux.
MATLAB has online documentation that states which versions of GCC compilers are supported by each MATLAB version (see https://www.mathworks.com/support/requirements/supported-compilers-linux.html).
However, MATLAB ships and links against its own versions of `libstdc++` and `libgfortran`, which may not actually support the compiler versions claimed in the online documentation.

Below, we enumerate what version of `libstdc++` MATLAB actually ships with, and therefore what GCC versions are actually supported by MATLAB. The relevant MATLAB libraries are stored in `$MATLAB_ROOT/sys/os/glnxa64/`.

| MATLAB | *claims to support* | GCC   | *but ships with* | `libstdc++` | *which supports* | GCC    | *or older* |
| ------ | ------------------- | ----- | ---------------- | ----------- | ---------------- | ------ | ---------- |
| R2025b |                     | 13.x  |                  | 6.0.30      |                  | 12.1.0 |            |
| R2025a |                     | 13.x  |                  | 6.0.30      |                  | 12.1.0 |            |
| R2024b |                     | 13.x  |                  | 6.0.30      |                  | 12.1.0 |            |
| R2024a |                     | 12.x  |                  | 6.0.28      |                  | 10.1.0 |            |
| R2023b |                     | 11.x  |                  | 6.0.28      |                  | 10.1.0 |            |
| R2023a |                     | 10.x  |                  | 6.0.28      |                  | 10.1.0 |            |
| R2022b |                     | 10.x  |                  | 6.0.28      |                  | 10.1.0 |            |
| R2022a |                     | 10.x  |                  | 6.0.28      |                  | 10.1.0 |            |
| R2021b |                     | 9.x   |                  | 6.0.25      |                  | 8.1.0  |            |
| R2021a |                     | 9.x   |                  | 6.0.25      |                  | 8.1.0  |            |
| R2020b |                     | 9.x   |                  | 6.0.25      |                  | 8.1.0  |            |
| R2020a |                     | 6.3.x |                  | 6.0.22      |                  | 6.1.0  |            |

The story for Fortran compilation is better. MATLAB's online documentation correctly states which `gfortran` versions are compatible with the version of `libgfortran` shipped with MATLAB.

| MATLAB | GCC   | `libgfortran` |
| ------ | ----- | ------------- |
| R2025b | 10.x  | 5.0.0         |
| R2025a | 10.x  | 5.0.0         |
| R2024b | 10.x  | 5.0.0         |
| R2024a | 10.x  | 5.0.0         |
| R2023b | 10.x  | 5.0.0         |
| R2023a | 10.x  | 5.0.0         |
| R2022b | 10.x  | 5.0.0         |
| R2022a | 10.x  | 5.0.0         |
| R2021b | 8.x   | 5.0.0         |
| R2021a | 8.x   | 5.0.0         |
| R2020b | 8.x   | 5.0.0         |
| R2020a | 6.3.x | 3.0.0         |

The upshot is that if we compile our MEX binaries on Linux using GCC version 8, then they should work out of the box on MATLAB R2020b and newer on Linux.

## GCC, GLIBCXX, and libstdc++ correspondence

The following table lists the version correspondence between GCC, `GLIBCXX`, `libstdc++`, and `libgfortran` (see https://gcc.gnu.org/onlinedocs/libstdc++/manual/abi.html). Missing entries indicate unknown version numbers.

Note: Major versions of `libstdc++` are forward compatibile. For example, `libstdc++.so.6.0.0` (corresponding to GCC 3.4.0) is compatible with `libstdc++.so.6.0.34` (corresponding to GCC 16.1.0).

| GCC    | `GLIBCXX` | `libstdc++` | `libgfortran` |
| ------ | --------- | ----------- | ------------- |
| 3.0.0  |           | 3.0.0       |               |
| 3.0.1  |           | 3.0.1       |               |
| 3.0.2  |           | 3.0.2       |               |
| 3.0.3  |           | 3.0.3       |               |
| 3.0.4  |           | 3.0.4       |               |
| 3.1.0  | 3.1       | 4.0.0       |               |
| 3.1.1  | 3.1       | 4.0.1       |               |
| 3.2.0  | 3.2       | 5.0.0       |               |
| 3.2.1  | 3.2.1     | 5.0.1       |               |
| 3.2.2  | 3.2.2     | 5.0.2       |               |
| 3.2.3  | 3.2.2     | 5.0.3       |               |
| 3.3.0  | 3.2.2     | 5.0.4       |               |
| 3.3.1  | 3.2.3     | 5.0.5       |               |
| 3.3.2  | 3.2.3     |             |               |
| 3.3.3  | 3.2.3     |             |               |
| 3.4.0  | 3.4       | 6.0.0       |               |
| 3.4.1  | 3.4.1     | 6.0.1       |               |
| 3.4.2  | 3.4.2     | 6.0.2       |               |
| 3.4.3  | 3.4.3     | 6.0.3       |               |
| 4.0.0  | 3.4.4     | 6.0.4       |               |
| 4.0.1  | 3.4.5     | 6.0.5       |               |
| 4.0.2  | 3.4.6     | 6.0.6       |               |
| 4.0.3  | 3.4.7     | 6.0.7       |               |
| 4.1.0  |           | 6.0.7       |               |
| 4.1.1  | 3.4.8     | 6.0.8       |               |
| 4.2.0  | 3.4.9     | 6.0.9       |               |
| 4.2.1  |           | 6.0.9       |               |
| 4.2.2  |           | 6.0.9       |               |
| 4.3.0  | 3.4.10    | 6.0.10      | 3.0.0         |
| 4.4.0  | 3.4.11    | 6.0.11      |               |
| 4.4.1  | 3.4.12    | 6.0.12      |               |
| 4.4.2  | 3.4.13    | 6.0.13      |               |
| 4.5.0  | 3.4.14    | 6.0.14      |               |
| 4.6.0  | 3.4.15    | 6.0.15      |               |
| 4.6.1  | 3.4.16    | 6.0.16      |               |
| 4.7.0  | 3.4.17    | 6.0.17      |               |
| 4.8.0  | 3.4.18    | 6.0.18      |               |
| 4.8.3  | 3.4.19    | 6.0.19      |               |
| 4.9.0  | 3.4.20    | 6.0.20      |               |
| 5.1.0  | 3.4.21    | 6.0.21      |               |
| 6.1.0  | 3.4.22    | 6.0.22      |               |
| 7.1.0  | 3.4.23    | 6.0.23      | 4.0.0         |
| 7.2.0  | 3.4.24    | 6.0.24      |               |
| 8.1.0  | 3.4.25    | 6.0.25      | 5.0.0         |
| 9.1.0  | 3.4.26    | 6.0.26      |               |
| 9.2.0  | 3.4.27    | 6.0.27      |               |
| 9.3.0  | 3.4.28    | 6.0.28      |               |
| 10.1.0 | 3.4.28    | 6.0.28      |               |
| 11.1.0 | 3.4.29    | 6.0.29      |               |
| 12.1.0 | 3.4.30    | 6.0.30      |               |
| 13.1.0 | 3.4.31    | 6.0.31      |               |
| 13.2.0 | 3.4.32    | 6.0.32      |               |
| 14.1.0 | 3.4.33    | 6.0.33      |               |
| 15.1.0 | 3.4.34    | 6.0.34      |               |
| 16.1.0 | 3.4.34    | 6.0.34      |               |
