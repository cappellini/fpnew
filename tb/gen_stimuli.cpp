/*
   Copyright 2022 - ETH Zurich. All rights reserved.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/

/* Contributor: Fabio Cappellini <fcappellini@ethz.ch>

    Generate a stimuli file for FPnew mixed precision testbench.
    Inputs are randomly generated using a uniform binary distribution.

    Requires flexfloat library to work: https://github.com/oprecomp/flexfloat

    Arguments (in order): nr_of_stimuli instruction src_fmt src2_fmt dst_fmt

    Valid instructions: SDOTP, VSUM, EXVSUM, FMADD

    Valid formats (fmt): FP32, FP16, AL16, FP8, AL8

    Known limitations: SDOTP, VSUM, and EXVSUM results are calculated using concatenated
    additions or fused multiply-add, which can lead to imprecise results.
*/ 


#define WIDTH 32

#include "flexfloat.hpp"
#include <cstdio>
#include <iostream>
#include <iomanip>
#include <algorithm>
#include <stdlib.h>
#include <fstream>
#include <limits>
#include <cassert>


const int INTMIN = std::numeric_limits<int>::min();
const int INTMAX = std::numeric_limits<int>::max();

const flexfloat_desc_t FP64    = {11,52};
const flexfloat_desc_t FP32    = {8, 23};
const flexfloat_desc_t FP16    = {5, 10};
const flexfloat_desc_t FP8     = {5,  2};
const flexfloat_desc_t FP16ALT = {8,  7};
const flexfloat_desc_t FP8ALT  = {4,  3};

enum operation_e {SDOTP, VSUM, EXVSUM, FMADD};

std::string to_string(operation_e operation){
    std::string s;
    switch(operation){
        case SDOTP: s = "SDOTP"; break;
        case VSUM: s = "VSUM"; break;
        case EXVSUM: s = "EXVSUM"; break;
        case FMADD: s = "FMADD"; break;
    }
    return s;
}

std::string to_string(flexfloat_desc_t desc){
    std::string s;
    if     (desc.exp_bits == 8 && desc.frac_bits == 23) s = "FP32 ";
    else if(desc.exp_bits == 5 && desc.frac_bits == 10) s = "FP16 ";
    else if(desc.exp_bits == 5 && desc.frac_bits ==  2) s = "FP08 ";
    else if(desc.exp_bits == 8 && desc.frac_bits ==  7) s = "AL16 ";
    else if(desc.exp_bits == 4 && desc.frac_bits ==  3) s = "AL08 ";
    else assert(0 && "Invalid FP format.");
    return s;
}

flexfloat_desc_t to_desc(std::string str){
    flexfloat_desc_t desc;

    const flexfloat_desc_t FP64    = {11,52};
    const flexfloat_desc_t FP32    = {8, 23};
    const flexfloat_desc_t FP16    = {5, 10};
    const flexfloat_desc_t FP8     = {5,  2};
    const flexfloat_desc_t FP16ALT = {8,  7};
    const flexfloat_desc_t FP8ALT  = {4,  3};

    if (str.compare("FP32") == 0){
        desc = FP32;
    } else if(str.compare("FP16") == 0){
        desc = FP16;
    } else if(str.compare("FP8") == 0){
        desc = FP8;
    } else if(str.compare("AL16") == 0){
        desc = FP16ALT;
    } else if(str.compare("AL8") == 0){
        desc = FP8ALT;
    } else{
        assert(0 && "Invalid FP format.");
    }
    return desc;
}

std::string ts(flexfloat_t *ff, int width){
    double value = ff_get_double(ff);
    ff_init_double(ff, value, ff->desc);
    flexfloat_desc_t desc = ff->desc;
    int ff_width = desc.exp_bits + desc.frac_bits + 1;
    int filler = (width - ff_width)/4;

    std::stringstream ss;
    std::string myString = ss.str();
    if(filler){
        ss << std::setfill('F') <<  std::setw(filler) << "";
    } 
    ss << std::setfill('0') << std::setw(ff_width/4) << std::right << std::hex << (unsigned int)flexfloat_get_bits(ff);
    return ss.str();
}


uint_t ff_set_random(flexfloat_t *obj){
    flexfloat_desc_t desc = obj->desc;
    int width_minus1 = desc.exp_bits + desc.frac_bits;
    std::random_device rd;
    std::mt19937 eng(rd());

    int_t min, max;
    int_t one = 1;
    if(width_minus1 + 1 == 32){
        min = INTMIN;
        max = INTMAX;
    } else {
        min = -(one<<width_minus1);
        max = (one<<width_minus1) - one;
    }
    std::uniform_int_distribution<> distr(min, max);
    uint_t binary = distr(eng);
    
    flexfloat_set_bits(obj, binary);
    return binary;
}

void ff_init_random(flexfloat_t *obj, flexfloat_desc_t desc){
    ff_init(obj, desc);
    ff_set_random(obj);
}


int main(int argc, char* argv[]){

    operation_e op = SDOTP;
    int nr_of_stimuli = 10;
    flexfloat_desc_t src_fmt = FP16;
    flexfloat_desc_t src2_fmt = FP16;
    flexfloat_desc_t dst_fmt = FP32;
    bool op_mod = false;

    if(argc > 1){
        nr_of_stimuli = std::stoi(argv[1]);
    }
    if(argc > 2){
        if(std::string(argv[2]).compare("SDOTP") == 0){
            op = SDOTP;
            src_fmt = FP16;
            src2_fmt = FP16;
            dst_fmt = FP32;
        } else if(std::string(argv[2]).compare("VSUM") == 0){
            op = VSUM;
            src_fmt = FP16;
            src2_fmt = FP16;
            dst_fmt = FP16;
        } else if(std::string(argv[2]).compare("EXVSUM") == 0){
            op = EXVSUM;
            src_fmt = FP16;
            src2_fmt = FP16;
            dst_fmt = FP32;
        } else if(std::string(argv[2]).compare("FMADD") == 0){
            op = FMADD;
            src_fmt = FP32;
            src2_fmt = FP32;
            dst_fmt = FP32;
        } 
    }
    if(argc > 5){
        src_fmt  = to_desc(argv[3]);
        src2_fmt = to_desc(argv[4]);
        dst_fmt  = to_desc(argv[5]);
    }

    std::ofstream file;
    file.open("../stimuli.txt", std::ios::out);

    file << "//operation op_mod src_fmt src2_fmt dst_fmt operands exp_result" << std::endl;

    bool is_vsum = op == VSUM;
    bool is_fma =  op == FMADD;

    flexfloat_desc_t a_fmt = is_fma ? src2_fmt : src_fmt;
    flexfloat_desc_t b_fmt = src2_fmt;
    flexfloat_desc_t c_fmt = src_fmt;
    flexfloat_desc_t d_fmt = is_vsum ? src_fmt : src2_fmt;
    flexfloat_desc_t e_fmt = dst_fmt;

    

    int dst_width = dst_fmt.exp_bits + dst_fmt.frac_bits + 1;

    bool is_8bit_exvsum =  (op == EXVSUM) && (dst_width == 8);

    int src_width = is_fma || is_8bit_exvsum ? dst_width : dst_width/2;

    std::string input, output, e_cc, d_cc, c_cc, b_cc, a_cc, db_cc, ca_cc, ca2_cc;

    flexfloat_t ff_a, ff_c, ff_b, ff_d, ff_e, ff_res;
    flexfloat_t a, b, c, d, e, res;

    ff_init(&ff_a, a_fmt);
    ff_init(&ff_b, b_fmt);
    ff_init(&ff_c, c_fmt);
    ff_init(&ff_d, d_fmt);
    ff_init(&ff_e, e_fmt);


    for(int k = 0; k < nr_of_stimuli; k++){
        input = "";
        output = "";

        e_cc = "";
        d_cc = "";
        c_cc = "";
        b_cc = "";
        a_cc = "";

        db_cc = "";
        ca_cc = "";
        ca2_cc = "";

        for(int i = 0; i < WIDTH/dst_width; i++){
            if(op == VSUM && dst_width == 8 && i >= WIDTH/16) break;
            uint_t a_bin = ff_set_random(&ff_a);
            uint_t b_bin = ff_set_random(&ff_b);
            uint_t c_bin = ff_set_random(&ff_c);
            uint_t d_bin = ff_set_random(&ff_d);
            uint_t e_bin = ff_set_random(&ff_e);


            ff_cast(&a, &ff_a, FP64);  
            ff_cast(&b, &ff_b, FP64);  
            ff_cast(&c, &ff_c, FP64);  
            ff_cast(&d, &ff_d, FP64);  
            ff_cast(&e, &ff_e, FP64);
            ff_init(&res, FP64);


            switch(op){
                case SDOTP:
                    ff_fma(&e, &a, &b, &e);    // e   = a*b + e
                    ff_fma(&res, &c, &d, &e);  // res = c*d + e
                    break;
                case VSUM:
                case EXVSUM:
                    ff_add(&e, &e, &a);        // e   = e + a
                    ff_add(&res, &e, &c);      // res = e + c
                    break;
                case FMADD:
                    ff_fma(&res, &a, &c, &e);  // res = a*c + e 
                    break;
            }

            ff_cast(&ff_res, &res, dst_fmt);


            if(op == VSUM && dst_width == 8) e_cc += "FF";
            e_cc += ts(&ff_e, dst_width);
            d_cc += ts(&ff_d, src_width); 
            c_cc += ts(&ff_c, src_width);
            b_cc += ts(&ff_b, src_width);
            a_cc += ts(&ff_a, src_width);

            db_cc += ts(&ff_d, src_width) + ts(&ff_b, src_width);
            if(op != VSUM || k % 2 == 0 || dst_width == 8) ca_cc += ts(&ff_c, src_width) + ts(&ff_a, src_width);
            else                         ca2_cc += ts(&ff_c, src_width) + ts(&ff_a, src_width);

            output += ts(&ff_res, dst_width);
        }

         if(op == VSUM && dst_width == 8){
            output = std::string(WIDTH/8, 'F') + output;
            ca2_cc = std::string(WIDTH/4, 'F');
        }


        switch(op){
            case SDOTP: 
                file << "SDOTP " << op_mod << " " << to_string(src_fmt) << to_string(src2_fmt) << to_string(dst_fmt) << e_cc << db_cc << ca_cc << " " <<  output << std::endl;
                break;
            case VSUM:
                if(dst_width == WIDTH){
                    file << "VSUM_ " << op_mod << " " << to_string(src_fmt) << to_string(src2_fmt) <<to_string(dst_fmt) << e_cc <<  c_cc << a_cc << " " << output << std::endl;
                } else {
                    file << "VSUM_ " << op_mod << " " << to_string(src_fmt) << to_string(src2_fmt) <<to_string(dst_fmt) << e_cc << ca2_cc << ca_cc << " " << output << std::endl;
                }                
                break;
            case EXVSUM:
                file << "EXVSU " << op_mod << " " << to_string(src_fmt) << to_string(src2_fmt) << to_string(dst_fmt) << e_cc << std::string(WIDTH/4, 'F') << ca_cc << " " <<  output << std::endl;
                break;
            case FMADD: 
                file << "FMADD " << op_mod << " " << to_string(src_fmt) << to_string(src2_fmt) <<to_string(dst_fmt) << e_cc << c_cc << a_cc << " " <<  output << std::endl;
                break;
            default:
                assert(0 && "Operation not supported yet.");
        }
    }

   file.close();

   std::cout << "Finished " << WIDTH << "-bit stimuli file generation." << std::endl;
   
   return 0;
}
