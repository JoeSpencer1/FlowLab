#=---------------------------------------------------------------
10/10/2022
Rotor Functions v3 Rotor_Functions.jl
This companion file for Rotor_Analysis will contain functions
used in the main file. They are mostly just conversion or airfoil
creation functions.
---------------------------------------------------------------=#

using CCBlade, FLOWMath, Xfoil, Plots, LaTeXStrings, DelimitedFiles

"""
# create
This function creates an airfoil and calculates its coefficients
of lift and drag at various points. So far this is just good for
NACA airfoils.
The name is the diameter x pitch.
"""
function create(; mpth = 4412, n = 14)
    nd = n * 1.0 # Converts n to a decimal.
    n2 = n * 2 + 1 # Gives total array length.
    x = Array{Float64}(undef, n2, 1) # x-coordinate array
    y = Array{Float64}(undef, n2, 1) # y-coordinate array
    for i in 1:n2  
        # Populates x array.
        if i < (n + 2) # Beginning items start at 1 and go down to 0
            x[i] = 1 - (i - 1) / nd
        end
        if i > (n + 1) # Entries in second half of list go back to 1
            x[i] = (i - n - 1) / nd
        end
    end
    th = mod(mpth, 100) / 100 # Last 2 digits describe thickness
    p = (mod(mpth, 1000) - th * 100) / 1000 # 2nd digit is p
    m = (mpth - p * 1000 - th* 100) / 100000 # 1st digit is m
    for i in 1:n2
        if i < n + 1 # This general equation is for top of fin
            y[i] = 5 * th * (0.2969 * sqrt(x[i]) - 0.1260 * x[i] - 0.3516 * x[i] ^ 2 + 0.2843 * x[i] ^ 3 - 0.1015 * x[i] ^ 4)
        end
        if i > n # Same general equation, for bottom of fin
            y[i] = -5 * th * (0.2969 * sqrt(x[i]) - 0.1260 * x[i] - 0.3516 * x[i] ^ 2 + 0.2843 * x[i] ^ 3 - 0.1015 * x[i] ^ 4)
        end
        if x[i] <= p # Fin adjustment at front
            y[i] += (2 * p * x[i] - x[i] ^ 2) * m / p ^ 2
        end
        if x[i] > p # Fin adjustmant at rear
            y[i] += ((1 - 2 * p) + 2 * p * x[i] - x[i] ^ 2) * m / (1 - p) ^ 2
        end
    end
    return x, y
end

"""
# coeff
This function finds the coefficients of an airfoil. Like create(),
it is borrowed from my Airfoil Analysis project.
"""
function coeff(x, y; increment = 1, iterations = 100, re = 1e6, min = -15, max = 15)
    alpha = min:increment:max # Establish values of alhpha over range
    # This next function finds various coefficients for the airfoil.
    c_l, c_d, c_dp, c_m, converged = Xfoil.alpha_sweep(x, y, alpha, re, iter=iterations, zeroinit=false, printdata=false)
    return alpha, c_l, c_d, c_dp, c_m, converged
end

"""
# rads
This simple function converts rpm to rad/s
"""
function rads(rpm)
    return rpm * 2 * pi / 60 # This allows you to call a function to convert.
end

"""
# rad
This function converts rad to degress.
"""
function rad(deg)
    return deg * pi / 180 # Simple multiplication for radians to degrees
end

"""
# rev
Convers deg to radians
"""
function rev(rad)
    return rad / (2 * pi) # Convert radians to revolutions.
end

"""
# TransonicDrag
This function, copied from Guided_Example.jl, finds the drag based on a mach number.
"""
struct TransonicDrag <: MachCorrection
    Mcc  # crest critical Mach number
end

"""
# Convert
This function multiplies a proportion by the propellor tip length.
"""
function Convert(geom, rtip)
    return geom[:] * rtip # This changes the geometry to terms of rtip instead of 1.
end

"""
# Loadexp
This function loads experimental data from a file.
"""
function Loadexp(filename) # Function designed to read 4-column experimental data.
    exp = readdlm(filename, '\t', Float64, '\n') # File is divided by tabs and endlines.
    Jexp = exp[:, 1] # J in first column
    CTexp = exp[:, 2] # CT in second column
    CPexp = exp[:, 3] # CP in third column
    etaexp = exp[:, 4] # eta in foruth column.
    return Jexp, CTexp, CPexp, etaexp
end

"""
# Loaddata
This function loads the data for a six-column xfoil file. Entries are separated by tabs.
"""
function Loaddata(filename)
    xfoildata = readdlm(filename, '\t', Float64, '\n') # Divided by tabs and newlines
    alpha = xfoildata[:, 1] * pi/180 # Convert degrees to radians
    cl = xfoildata[:, 2] # cl in 2nd column
    cd = xfoildata[:, 3] # cd in 3rd column
    return alpha, cl, cd
end

"""
# intom
This function converts the tip radius in inches to meters.
"""
function intom(Rtip)
    return Rtip / 2.0 * 0.254 # Also converts diameter to radius.
end

"""
# CQCP
This function does the simple calculation to convert CQ to CP. CQ = CP/2pi
"""
function CQCP(CP)
    CQ = CP / (2 * pi) # Performs arithmetic
    return CQ
end

"""
# CPCQ
This function Converts CP to CQ. CP = CQ * 2pi
"""
function CPCQ(CQ)
    CP = CQ * (2 * pi) # Perform arithmetic
    return CP
end

"""
# CTCPeff
This function finds the coefficients of Thrust, Power, and Efficiency at different angles.
"""
function CDCPeff(rpm, rotor, sections, r, D; nJ = 20, rho = 1.225)
    Omega = rad(rpm) # Rotational Velocity in rad/s
    J = range(0.1, 0.6, length = nJ)  # advance ratio
    n = rev(Omega) # Convert rad/s to rev/s
    eff = zeros(nJ) # Zeros vector for efficiency
    CT = zeros(nJ) # Zeros vector for CT
    CQ = zeros(nJ) # Zeros vector for CQ
    for i = 1:nJ
        local Vinf = J[i] * D * n # Calculates freestream velocity
        local op = simple_op.(Vinf, Omega, r, rho) # Create operating point object to solve
        outputs = solve.(Ref(rotor), sections, op) # Solves op from previous line
        T, Q = thrusttorque(rotor, sections, outputs) # Integrate the area of the calucalted curve
        eff[i], CT[i], CQ[i] = nondim(T, Q, Vinf, Omega, rho, rotor, "propeller") # Nondimensionalize output to make useable data
    end
    return J, eff, CT, CQ
end

"""
# Compute
The compute function finds J, eff, CT, and CQ for a rotor of provided geometry.
"""
function Compute(Rtip; Rhub = 0.10, Re0 = 1e6, B = 2, rpm = 5400, filename = "/Users/joe/Documents/GitHub/497R-Projects/Rotor Analysis/Rotors/APC_10x7.txt", twist = 0)
    # The first section creates the propellor.
    Rtip = intom(Rtip)  # Diameter to radius, inches to meters
    Rhub = Rhub * Rtip # Hub radius assumed 10% of tip radius
    rotor = Rotor(Rhub, Rtip, B) # Create rotor
    D = 2 * Rtip # Diameter to radius

    # Propellor geometry
    propgeom = readdlm(filename)
    r = Convert(propgeom[:, 1], Rtip) # Translate geometry from propellor percentatge to actual distance
    chord = Convert(propgeom[:, 2], Rtip) # Translate chord to actual distance
    theta = rad(propgeom[:, 3]) # Convert degrees to radians
    # Find airfoil data at a variety of attack angles
    af = AlphaAF("/Users/joe/Documents/GitHub/497R-Projects/Rotor Analysis/Rotors/naca4412.dat")

    # This section adds twist to a propellor's twist distribution if applicable.
    if twist != 0
        for i in eachindex(theta)
            theta[i] += twist # Add twist to each segment.
        end
    end

    # This section reads in experimental data and estimates results.
    sections = Section.(r, chord, theta, Ref(af)) # Define properties for individual sections
    J, eff, CT, CQ = CDCPeff(rpm, rotor, sections, r, D) # This is an internal function in this file.

    # Return these outputs.
    return J, eff, CT, CQ
end