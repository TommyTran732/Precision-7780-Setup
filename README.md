# Precision-7780-Setup
My personal setup for the Precision 7780 [WIP]

## Hardware
- **CPU**: Intel® Core™ i9-13950HX Processor
- **GPU**: NVIDIA GeForce RTX 4090 Mobile
- **RAM**: 2x Micron 32GB DDR5-5600 ECC (MTC20C2085S1TC56BD1R)
- **Drive 1**: Micron 3500 2TB (MTFDKBA2T0TGD-1BK1AABYYR)
- **Drive 2**: Micron 3500 1TB (MTFDKBA1T0TGD-1BK1AABYYR)
- **Drive 3**: Micron 3500 1TB (MTFDKBA1T0TGD-1BK1AABYYR)
- **Drive 4**: Micron 3500 1TB (MTFDKBA1T0TGD-1BK1AABYYR)

**Notes**: 

As of this writing, the Micron 3500 are the only client SSDs advertising [firmware verification](https://www.micron.com/content/dam/micron/global/public/documents/products/product-flyer/micron-ssd-secure-foundation-flyer.pdf). I am not sure how secure the implementation is, but I guess it is better than nothing.

There are other enterprise SSDs from Micron with firmware verification, but I am not using them here due to heat and power constraints.

Unlike the likes of WD and Samsung who make life extremely difficult unless you buy an OEM drive, Micron [provides firmware updates on their website and also includes an update utility for Linux](https://www.micron.com/products/storage/ssd/micron-ssd-firmware#accordion-e6c186b05b-item-2ebc81f38a). There is no need to look for a Dell or Lenovo version of the drive to get updates via LVFS.
