
module MDForce {

use MDSystem;
	enum ForceStyle { FORCELJ, FORCEEAM };

	class Force {
		var cutforce, cutforcesq, eng_vdwl : real;
		var virial, mass : real; // virial is average kinetic energy over time, see 'Virial theorem'
		var reneigh : int;

		var style : ForceStyle;

		proc Force();
		proc compute(sys : System, evflag : bool) : void {}
	}

	// 'Embedded atom model'
	class ForceEAM : Force  {
		var cutmax : real;
		var nrho, nr : int;

		// potentials as array data
		var rSpace : domain(1);
		var frhoSpace : domain(1);
		var frho : [frhoSpace] real;
		var rhor, z2r : [rSpace] real;
		
		// spline form for computation
		var dr, rdr, drho, rdrho : real;
		var splineSpace : domain(1);
		var frSplineSpace : domain(1);
		var rzSplineSpace : domain(1);
		var rhor_spline, z2r_spline : [rzSplineSpace] real;
		var frho_spline : [frSplineSpace] real;
		
		var rfSpace : domain(1);
		var rho, fp : [rfSpace] real;
		var nmax : int;
		var map : [1..10] int;
		
		class Funcfl {
			var ffile : string;
			var nrho, nr : int;
			var drho, dr, cut, mass : real;
			var zrSpace : domain(1);
			var frhoSpace : domain(1);
			var frho : [frhoSpace] real;
			var rhor, zr : [zrSpace] real;
		} 

		var funcfl : Funcfl;

		proc ForceEAM(cf : real) {
			cutforce = cf;
			cutforcesq = cf*cf;
			nmax = 0;
			coeff("Cu_u6.eam");
			init_style();
			style = ForceStyle.FORCEEAM;
		}

		proc coeff(fname : string) {
			funcfl = new Funcfl();
			funcfl.ffile = fname;
			var fchan = open(fname, iomode.r);
			var rd = fchan.reader();

			rd.readln(); // skip header info
			rd.read(int); // skip atomic number
			funcfl.mass = rd.readln(real);
			mass = funcfl.mass;
			(funcfl.nrho, funcfl.drho, funcfl.nr, funcfl.dr, funcfl.cut) = rd.readln(int,real,int,real,real);
			funcfl.frhoSpace = {1..(funcfl.nrho+1)};
			funcfl.zrSpace = {1..(funcfl.nr+1)};
			grab(rd, funcfl.frho); // verified correctness
			grab(rd, funcfl.zr);
			grab(rd, funcfl.rhor);
			cutmax = funcfl.cut;
			cutforcesq = cutmax * cutmax;
		}

		proc init_style() {
			file2array();
			array2spline();
		}

		proc file2array() {
			var i, j, k, m, n : int;
			var ntypes = 1;
			var sixth : real = 1.0 / 6.0;

			var active = 0;
			var rmax, rhomax : real;
			dr = 0;
			drho = 0;
			rmax = 0;
			rhomax = 0;

			dr = max(dr, funcfl.dr);
			drho = max(drho, funcfl.drho);
			rmax = max(rmax, (funcfl.nr - 1) * funcfl.dr);
			rhomax = max(rhomax, (funcfl.nrho - 1) * funcfl.drho);

			nr = (rmax / dr + .5) : int;
			nrho = (rhomax / drho + .5) : int;

			frhoSpace = {1..(nrho+1)};

			var r, p, cof1, cof2, cof3, cof4 : real;

			for (f,m) in zip(frho[2..], 2.. ) {
				m -= 1; // get us to 0-based C arrays.
				r = (m - 1) * drho;
				p = r / funcfl.drho + 1.0;
				k = p : int;
				k = min(k, funcfl.nrho-2);
				k = max(k, 2);
				p -= k;
				p = min(p, 2.0);
				cof1 = -sixth * p * (p-1.0) * (p-2.0);
				cof2 = 0.5 * (p * p - 1.0) * (p - 2.0);
				cof3 = -.5 * p * (p+1.0) * (p - 2.0);
				cof4 = sixth * p * (p * p - 1.0);
				k += 1; // get us to 1-based chapel arrays.
				f = cof1 * funcfl.frho[k-1] + cof2 * funcfl.frho[k] + cof3 * funcfl.frho[k + 1] + cof4 * funcfl.frho[k+2];
			} // verified correct

			rSpace = {1..(nr+1)};
			for (f,m) in zip(rhor[2..], 2..) {
				m -= 1;
				r = (m - 1) * dr;
				p = r / funcfl.dr + 1.0;
				k = p : int;
				k = min(k, funcfl.nr - 2);
				k = max(k, 2);
				p -= k;
				p = min(p, 2.0);
				cof1 = -sixth * p * (p-1.0) * (p-2.0);
				cof2 = 0.5 * (p * p - 1.0) * (p - 2.0);
				cof3 = -.5 * p * (p+1.0) * (p - 2.0);
				cof4 = sixth * p * (p * p - 1.0);
				k += 1;
				f = cof1 * funcfl.rhor[k-1] + cof2 * funcfl.rhor[k] + cof3 * funcfl.rhor[k+1] + cof4 * funcfl.rhor[k+2];
			}

			for (f,m) in zip(z2r[2..], 2..) {
				m -= 1;
				r = (m - 1) * dr;
				p = r / funcfl.dr + 1.0;
				k = p : int;
				k = min(k, funcfl.nr - 2);
				k = max(k, 2);
				p -= k;
				p = min(p,2.0);
				cof1 = -sixth * p * (p - 1.0) * (p - 2.0);
				cof2 = 0.5 * (p * p - 1.0) * (p - 2.0);
				cof3 = -.5 * p * (p+1.0) * (p - 2.0);
				cof4 = sixth * p * (p * p - 1.0);
				k += 1;
				var zri : real = cof1 * funcfl.zr[k-1] + cof2 * funcfl.zr[k] + cof3 * funcfl.zr[k+1] + cof4 * funcfl.zr[k+2];
				f = 27.2 * 0.529 * zri * zri;
			} 
		}

		proc array2spline() {
			rdr = 1.0 / dr;
			rdrho = 1.0 / drho;

			frSplineSpace = {0..((nrho+1) * 7)-1};
			rzSplineSpace = {0..((nr+1) * 7)-1};

			interp(nrho, drho, frho, frho_spline);
			interp(nr, dr, rhor, rhor_spline);
			interp(nr, dr, z2r, z2r_spline);
		}

		// copied straight from c++, not entirely sure what it does
		proc interp(n : int, delta : real, arr : [] real, spline : [] real) {
			for (f,m) in zip(arr[2..],1..) {
				spline[m*7 + 6] = f;
			}

			spline[1*7 + 5] = spline[2*7+6] - spline[1*7+6];
			spline[2 * 7 + 5] = 0.5 * (spline[3 * 7 + 6] - spline[1 * 7 + 6]);
			spline[(n - 1) * 7 + 5] = 0.5 * (spline[n * 7 + 6] - spline[(n - 2) * 7 + 6]);
			spline[n * 7 + 5] = spline[n * 7 + 6] - spline[(n - 1) * 7 + 6];

			for m in 3..n-2 {
				spline[m * 7 + 5] = ((spline[(m - 2) * 7 + 6] - spline[(m + 2) * 7 + 6]) +
					8.0 * (spline[(m + 1) * 7 + 6] - spline[(m - 1) * 7 + 6])) / 12.0;
			}

			for m in 1..n-1 {
				 spline[m * 7 + 4] = 3.0 * (spline[(m + 1) * 7 + 6] - spline[m * 7 + 6]) -
					 2.0 * spline[m * 7 + 5] - spline[(m + 1) * 7 + 5];
				 spline[m * 7 + 3] = spline[m * 7 + 5] + spline[(m + 1) * 7 + 5] -
					 2.0 * (spline[(m + 1) * 7 + 6] - spline[m * 7 + 6]);
			}

			spline[n*7 + 4] = 0.0;
			spline[n*7 + 3] = 0.0;

			for m in 1..n {
				spline[m * 7 + 2] = spline[m * 7 + 5] / delta;
				spline[m * 7 + 1] = 2.0 * spline[m * 7 + 4] / delta;
				spline[m * 7 + 0] = 3.0 * spline[m * 7 + 3] / delta;
			}
		}

		proc grab(rd,list : [] real) {
			for a in list[2..list.domain.high] {
				a = rd.read(real);
			}
			list[1] = list[2];
		}

		// combines halfneigh and fullneigh versions from c++
		proc compute(sys : System, evflag : bool) {
			var evdwl : real = 0.0;
			virial = 0;

			// adjust to accomodate changes in # ghosts
			if rfSpace.high < sys.natoms + sys.ghostSpace.high {
				rfSpace = {1..sys.natoms + sys.ghostSpace.high};
			}

			if sys.con.half_neigh {
				forall a in sys.atoms {
					a.f.zero();
				}
			}

			rho = 0;
			// accumulate densities for each atom
			for i in sys.atoms.domain {
				var a = sys.atoms[i];
				var rhoi : real = 0.0;
				for q in 1..a.ncount {
					var j = a.neighs[q];
					var n : atom;
					var nx : v3;
					var gi : int;
					if j <= sys.natoms {
						n = sys.atoms[j];
						nx = n.x;
					} else {
						nx = sys.ghosts[j-sys.natoms](2);
						gi = sys.ghosts[j-sys.natoms](1);
						nx = nx + sys.atoms[gi].x;
					}

					var del = a.x - nx;
					var rsq = del.dot(del);

					if rsq < cutforcesq {
						var p = sqrt(rsq) * rdr + 1.0;
						var m : int = p : int;
						if m >= nr - 1 then m = nr - 1;
						p -= m;
						if p >= 1.0 then p = 1.0;
						var val : real = ((rhor_spline[m*7 + 3] * p + rhor_spline[m * 7 + 4]) * p + rhor_spline[m*7+5]) * p + rhor_spline[m*7+6];
						rhoi += val;
						if j <= sys.natoms && sys.con.half_neigh { // not a ghost?
							rho[j] += val;
						}
					}
				}
				rho[i] += rhoi;
			} // end of first atom pass

			// process densities
			for (f,r) in zip(fp,rho) {
				var p = 1.0 * r * rdrho + 1.0;
				var m : int = p : int;
				m = max(1, min(m, nrho - 1));
				p -= m;
				p = min(p,1.0);
				f = (frho_spline[m*7+0] * p + frho_spline[m*7 + 1]) * p + frho_spline[m*7 + 2];

				if evflag {
					evdwl += ((frho_spline[m*7+3] * p + frho_spline[m*7+4]) * p + frho_spline[m*7+5]) * p + frho_spline[m*7+6];
				}
			} // end of second pass

			// communicate atoms (update ghosts)
			for (g,i) in zip(sys.ghosts,sys.ghostSpace) {
				fp[sys.natoms+i] = fp[g(1)];
			}

			// apply forces
			for i in sys.atoms.domain {
				var a = sys.atoms[i];
				var fx, fy, fz : real;
				for q in 1..a.ncount {
					var j = a.neighs[q];
					var n : atom;
					var nx : v3;
					var gi : int;
					if j <= sys.natoms {
						n = sys.atoms[j];
						nx = n.x;
					} else {
						nx = sys.ghosts[j-sys.natoms](2);
						gi = sys.ghosts[j-sys.natoms](1);
						nx = nx + sys.atoms[gi].x;
					}

					var del = a.x - nx;
					var rsq = del.dot(del);

					if rsq < cutforcesq {
						var r = sqrt(rsq);
						var p = r * rdr + 1.0;
						var m : int = p : int;
						if m >= nr - 1 then m = nr - 1;
						p -= m;
						if p >= 1.0 then p = 1.0;

						var rhoip = (rhor_spline[m * 7 + 0] * p + rhor_spline[m*7+1]) * p + rhor_spline[m*7 + 2];
						var z2p = (z2r_spline[m * 7 + 0] * p + z2r_spline[m * 7 + 1]) * p + z2r_spline[m * 7 + 2];
						var z2 = ((z2r_spline[m * 7 + 3] * p + z2r_spline[m * 7 + 4]) * p + z2r_spline[m * 7 + 5]) * p + z2r_spline[m*7+6];

						var recip = 1.0/r;
						var phi = z2 * recip;
						var phip = z2p * recip - phi * recip;
						var psip = fp[i] * rhoip + fp[j] * rhoip + phip;
						var fpair = -psip * recip;

						fx += del.x * fpair;
						fy += del.y * fpair;
						fz += del.z * fpair;

						if j <= sys.natoms && sys.con.half_neigh {
							n.f.x -= del.x * fpair;
							n.f.y -= del.y * fpair;
							n.f.z -= del.z * fpair;
						} else fpair *= .5;

						if evflag {
							virial += rsq * fpair;
							if !sys.con.half_neigh then evdwl += .5 * phi;
						}

						if sys.con.half_neigh {
							if j <= sys.natoms then evdwl += phi;
							else evdwl += .5 * phi;
						}
					}
				}
				if sys.con.half_neigh {
					a.f.x += fx;
					a.f.y += fy;
					a.f.z += fz;
				} else {
					a.f.x = fx;
					a.f.y = fy;
					a.f.z = fz;
				}
			} // end of third pass
			if sys.con.half_neigh then eng_vdwl = evdwl;
			else eng_vdwl += 2.0 * evdwl;
		}
		
	}

	// Lennard-Jones potential
	class ForceLJ : Force {
		var scale : real = 1.0;

		proc ForceLJ(cf : real) {
			cutforce = cf;
			cutforcesq = cf * cf;
			reneigh = 1;
			style = ForceStyle.FORCELJ;
		}

		proc compute(sys : System, evflag : bool) : void {
			eng_vdwl = 0;
			virial = 0;

			// wipe old forces
			forall a in sys.atoms {
				a.f.x = 0;
				a.f.y = 0;
				a.f.z = 0;
			}

			// for each atom, compute force between itself and its neighbors
			// can make outer loop parallel if we can make force modifications atomic
			for a in sys.atoms {
				var fx, fy, fz : real;
				for q in 1..a.ncount { 
					var j = a.neighs[q];
					var nx : v3;
					var gi : int;

					// handle ghost
					if j <= sys.natoms {
						nx = sys.atoms[j].x;
					} else {
						nx = sys.ghosts[j-sys.natoms](2);
						gi = sys.ghosts[j-sys.natoms](1);
						nx = nx + sys.atoms[gi].x;
					}

					var del = a.x - nx;
					var rsq = del.dot(del);

					// if the atoms are close enough, do some physics
					if rsq < cutforcesq {
						var sr2: real = 1.0 / rsq;
						var sr6 : real = sr2 * sr2 * sr2;
						var force : real = 48.0 * sr6 * (sr6 - .5) * sr2;
						var rx = del.x * force;
						var ry = del.y * force;
						var rz = del.z * force;
						fx += rx;
						fy += ry;
						fz += rz;

						// this needs to be atomic
						if sys.con.half_neigh {
							if j <= sys.natoms {
								sys.atoms[j].f.x -= rx;
								sys.atoms[j].f.y -= ry;
								sys.atoms[j].f.z -= rz;
							} else if sys.ghost_newton {
								sys.atoms[gi].f.x -= rx;
								sys.atoms[gi].f.y -= ry;
								sys.atoms[gi].f.z -= rz;
							}
						}
						if evflag { // if we care about data this iteration
							if sys.con.half_neigh {
								if sys.ghost_newton || j <= sys.natoms then scale = 1.0;
								else scale = .5;
								eng_vdwl += scale * (4.0 * sr6 * (sr6 - 1.0));
								virial += scale * rsq * force;
							} else { // fullneigh
								eng_vdwl += 4.0 * sr6 * (sr6 - 1.0);
								virial += .5 * rsq * force;
							}
						}
					}
				}
				a.f.x += fx;
				a.f.y += fy;
				a.f.z += fz;
			}

		}
	} 
}
