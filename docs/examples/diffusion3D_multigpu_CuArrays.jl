using ImplicitGlobalGrid, CUDA, Plots

@views d_xa(A) = A[2:end  , :     , :     ] .- A[1:end-1, :     , :     ];
@views d_xi(A) = A[2:end  ,2:end-1,2:end-1] .- A[1:end-1,2:end-1,2:end-1];
@views d_ya(A) = A[ :     ,2:end  , :     ] .- A[ :     ,1:end-1, :     ];
@views d_yi(A) = A[2:end-1,2:end  ,2:end-1] .- A[2:end-1,1:end-1,2:end-1];
@views d_za(A) = A[ :     , :     ,2:end  ] .- A[ :     , :     ,1:end-1];
@views d_zi(A) = A[2:end-1,2:end-1,2:end  ] .- A[2:end-1,2:end-1,1:end-1];
@views  inn(A) = A[2:end-1,2:end-1,2:end-1]

@views function diffusion3D()
    # Physics
    lam        = 1.0;                                       # Thermal conductivity
    cp_min     = 1.0;                                       # Minimal heat capacity
    lx, ly, lz = 10.0, 10.0, 10.0;                          # Length of computational domain in dimension x, y and z

    # Numerics
    nx, ny, nz = 256, 256, 256;                             # Number of gridpoints in dimensions x, y and z
    nt         = 100000;                                    # Number of time steps
    me, dims   = init_global_grid(nx, ny, nz);              # Initialize the implicit global grid
    dx         = lx/(nx_g()-1);                             # Space step in dimension x
    dy         = ly/(ny_g()-1);                             # ...        in dimension y
    dz         = lz/(nz_g()-1);                             # ...        in dimension z

    # Array initializations
    T     = CUDA.zeros(Float64, nx,   ny,   nz  );
    Cp    = CUDA.zeros(Float64, nx,   ny,   nz  );
    dTedt = CUDA.zeros(Float64, nx-2, ny-2, nz-2);
    qx    = CUDA.zeros(Float64, nx-1, ny-2, nz-2);
    qy    = CUDA.zeros(Float64, nx-2, ny-1, nz-2);
    qz    = CUDA.zeros(Float64, nx-2, ny-2, nz-1);

    # Initial conditions (heat capacity and temperature with two Gaussian anomalies each)
    Cp .= cp_min .+ CuArray([5*exp(-((x_g(ix,dx,Cp)-lx/1.5))^2-((y_g(iy,dy,Cp)-ly/2))^2-((z_g(iz,dz,Cp)-lz/1.5))^2) +
                             5*exp(-((x_g(ix,dx,Cp)-lx/3.0))^2-((y_g(iy,dy,Cp)-ly/2))^2-((z_g(iz,dz,Cp)-lz/1.5))^2) for ix=1:size(T,1), iy=1:size(T,2), iz=1:size(T,3)])
    T  .= CuArray([100*exp(-((x_g(ix,dx,T)-lx/2)/2)^2-((y_g(iy,dy,T)-ly/2)/2)^2-((z_g(iz,dz,T)-lz/3.0)/2)^2) +
                    50*exp(-((x_g(ix,dx,T)-lx/2)/2)^2-((y_g(iy,dy,T)-ly/2)/2)^2-((z_g(iz,dz,T)-lz/1.5)/2)^2) for ix=1:size(T,1), iy=1:size(T,2), iz=1:size(T,3)])

    # Preparation of visualisation
    gr()
    ENV["GKSwstype"]="nul"
    anim = Animation();
    nx_v = (nx-2)*dims[1];
    ny_v = (ny-2)*dims[2];
    nz_v = (nz-2)*dims[3];
    T_v  = zeros(nx_v, ny_v, nz_v);
    T_nohalo = zeros(nx-2, ny-2, nz-2);

    # Time loop
    dt = min(dx*dx,dy*dy,dz*dz)*cp_min/lam/8.1;                                               # Time step for the 3D Heat diffusion
    for it = 1:nt
        if mod(it, 1000) == 1                                                                 # Visualize only every 1000th time step
            T_nohalo .= Array(T[2:end-1,2:end-1,2:end-1]);                                    # Copy data to CPU removing the halo.
            gather!(T_nohalo, T_v)                                                            # Gather data on process 0 (could be interpolated/sampled first)
            if (me==0) heatmap(transpose(T_v[:,ny_v÷2,:]), aspect_ratio=1); frame(anim); end  # Visualize it on process 0.
        end
        qx    .= -lam.*d_xi(T)./dx;                                                           # Fourier's law of heat conduction: q_x   = -λ δT/δx
        qy    .= -lam.*d_yi(T)./dy;                                                           # ...                               q_y   = -λ δT/δy
        qz    .= -lam.*d_zi(T)./dz;                                                           # ...                               q_z   = -λ δT/δz
        dTedt .= 1.0./inn(Cp).*(-d_xa(qx)./dx .- d_ya(qy)./dy .- d_za(qz)./dz);               # Conservation of energy:           δT/δt = 1/cₚ (-δq_x/δx - δq_y/dy - δq_z/dz)
        T[2:end-1,2:end-1,2:end-1] .= inn(T) .+ dt.*dTedt;                                    # Update of temperature             T_new = T_old + δT/δt
        update_halo!(T);                                                                      # Update the halo of T
    end

    # Postprocessing
    if (me==0) gif(anim, "diffusion3D.gif", fps = 15) end                                     # Create a gif movie on process 0.
    if (me==0) mp4(anim, "diffusion3D.mp4", fps = 15) end                                     # Create a mp4 movie on process 0.
    finalize_global_grid();                                                                   # Finalize the implicit global grid
end

diffusion3D()
