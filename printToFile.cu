#include <string.h>
#include <stdio.h>
#include <sstream>
#include <fstream>
#include <thrust/reduce.h>
#include "printToFile.cuh"
#include "custom_cutil_math.h"
#include "SPHCudaUtils.h"
using namespace std;


real_ AngleF3F3(real3 a, real3 b) {
	return acos(dot(a, b));
}
//*******************************************************************************************************************************
//builds the neighbors' list of each particle and finds the force on each particle
//calculates the interaction force between 1- fluid-fluid, 2- fluid-solid, 3- solid-fluid particles
//calculates forces from other SPH or solid particles, as wall as boundaries
void PrintToFile(
		thrust::device_vector<real3> & posRadD,
		thrust::device_vector<real4> & velMasD,
		thrust::device_vector<real4> & rhoPresMuD,
		const thrust::host_vector<int3> & referenceArray,
		const thrust::device_vector<int> & rigidIdentifierD,
		thrust::device_vector<real3> & posRigidD,
		thrust::device_vector<real3> & posRigidCumulativeD,
		thrust::device_vector<real4> & velMassRigidD,
		thrust::device_vector<real4> & qD1,
		thrust::device_vector<real3> & AD1,
		thrust::device_vector<real3> & AD2,
		thrust::device_vector<real3> & AD3,
		thrust::device_vector<real3> & omegaLRF_D,
		real3 cMax,
		real3 cMin,
		SimParams paramsH,
		real_ delT,
		int tStep,
		real_ channelRadius,
		real2 channelCenterYZ) {
	thrust::host_vector<real3> posRadH = posRadD;
	thrust::host_vector<real4> velMasH = velMasD;
	thrust::host_vector<real4> rhoPresMuH = rhoPresMuD;
	thrust::host_vector<int> rigidIdentifierH = rigidIdentifierD;
	thrust::host_vector<real3> posRigidH = posRigidD;
	thrust::host_vector<real3> posRigidCumulativeH = posRigidCumulativeD;
	thrust::host_vector<real4> velMassRigidH = velMassRigidD;
	thrust::host_vector<real4> qH1 = qD1;
	thrust::host_vector<real3> omegaLRF_H = omegaLRF_D;
//////-+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++com
	ofstream fileNameFluid;
	int stepSaveFluid = 200000;
	if (tStep % stepSaveFluid == 0) {
		if (tStep / stepSaveFluid == 0) {
			fileNameFluid.open("dataFluid.txt");
			fileNameFluid<<"variables = \"x\", \"y\", \"z\", \"Vx\", \"Vy\", \"Vz\", \"Velocity Magnitude\", \"Rho\", \"Pressure\", \"type\"\n";
		} else {
			fileNameFluid.open("dataFluid.txt", ios::app);
		}

		fileNameFluid<<"zone\n";
		stringstream ssFluid;
		for (int i = referenceArray[0].x; i < referenceArray[1].y; i++) {
			real3 pos = posRadH[i];
			real3 vel = R3(velMasH[i]);
			real4 rP = rhoPresMuH[i];
			real_ velMag = length(vel);
			ssFluid<< pos.x<<", "<< pos.y<<", "<< pos.z<<", "<< vel.x<<", "<< vel.y<<", "<< vel.z<<", "<< velMag<<", "<< rP.x<<", "<< rP.y<<", "<< rP.w << endl;
		}
		fileNameFluid<<ssFluid.str();
		fileNameFluid.close();
	}
////-+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
	ofstream fileNameRigidsSPH;
	int stepSaveRigid = 10000;
	///if (tStep % 20 == 0 && tStep > 56000) {
	//if (tStep > 12506) {
	if (tStep % stepSaveRigid == 0) {
		if (tStep / stepSaveRigid == 0) {
			fileNameRigidsSPH.open("dataRigidParticle.txt");
			fileNameRigidsSPH<<"variables = \"x\", \"y\", \"z\", \"Vx\", \"Vy\", \"Vz\", \"Velocity Magnitude\", \"OmegaX\", \"OmegaY\", \"OmegaZ\", \"Rho\", \"Pressure\", \"bodySize\", \"type\"\n";

//			fprintf(
//					fileNameRigidsSPH,
//					);
		} else {
			fileNameRigidsSPH.open("dataRigidParticle.txt", ios::app);
		}
		fileNameRigidsSPH<<"zone\n";
		//fprintf(fileNameRigidsSPH, "zone\n");
		stringstream ssRigidsSPH;
		if (referenceArray.size() > 2) {
			const int numRigidBodies = posRigidH.size();
			int startRigidParticle = (referenceArray[2]).x;

			for (int i = startRigidParticle; i < referenceArray[2 + numRigidBodies - 1].y; i++) {
				real3 pos = posRadH[i];
				real3 vel = R3(velMasH[i]);
				//printf("velocccc %f %f %f\n", vel.x, vel.y, vel.z);
				real4 rP = rhoPresMuH[i];
				real_ velMag = length(vel);
				int rigidID = rigidIdentifierH[i - startRigidParticle];
				real3 posRigid = posRigidH[rigidID];
				real3 omega = omegaLRF_H[rigidID];
				real_ fakeRad = 9;
				ssRigidsSPH<<pos.x<<", "<< pos.y<<", "<< pos.z<<", "<<vel.x<<", "<<vel.y<<", "<< vel.z<<", "<< velMag<<", "<<omega.x<<", "<< omega.y<<", "<< omega.z<<", "<< rP.x<<", "<< rP.y<<", "<<fakeRad<<", "<< rP.w<<endl;

//				fprintf(fileNameRigidsSPH, "%f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f\n", pos.x, pos.y, pos.z, vel.x, vel.y, vel.z, velMag,
//						omega.x, omega.y, omega.z, rP.x, rP.y, fakeRad, rP.w);
			}
		}
		fileNameRigidsSPH<<ssRigidsSPH.str();
		fileNameRigidsSPH.close();
	//	fflush(fileNameRigidsSPH);
		//fclose(fileNameRigidsSPH);
	}
//////-+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
	ofstream fileNameSlice;
	int stepSaveFluidSlice = 50000; //1;//20000;
	//if (tStep%100 == 0 &&  tStep > 20400) {
	//if (tStep > 49100) {
	if (tStep % stepSaveFluidSlice == 0) {
		//if (tStep / stepSaveFluidSlice == 49101) {
		if (tStep / stepSaveFluidSlice == 0) {
			fileNameSlice.open("dataTotalSlice.txt");
			fileNameSlice<<"variables = \"x\", \"y\", \"z\", \"Vx\", \"Vy\", \"Vz\", \"Velocity Magnitude\", \"Rho\", \"Pressure\", \"type\"\n";
		} else {
			fileNameSlice.open("dataTotalSlice.txt", ios::app);
		}
		fileNameSlice<<"zone\n";
		stringstream ssSlice;
		for (int i = referenceArray[0].x; i < referenceArray[referenceArray.size() - 1].y; i++) {
			real3 posRad = posRadH[i];
			real3 pos = posRad;
			real_ rad = HSML;
			real3 vel = R3(velMasH[i]);
			real4 rP = rhoPresMuH[i];
			real_ velMag = length(vel);
			if ((pos.y < cMin.y + 0.5 * (cMax.y - cMin.y) + 3 * rad) && (pos.y > cMin.y + 0.5 * (cMax.y - cMin.y) - 3 * rad)) {
				ssSlice<< pos.x<<", "<< pos.y<<", "<< pos.z<<", "<< vel.x<<", "<< vel.y<<", "<< vel.z<<", "<< velMag<<", "<< rP.x<<", "<< rP.y<<", "<< rP.w<<endl;
			}
		}
		fileNameSlice<<ssSlice.str();
		fileNameSlice.close();
	}
////////-+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++//comcom
//	ofstream fileNameCartesianTotal;
//	thrust::host_vector<real4> rho_Pres_CartH(1);
//	thrust::host_vector<real4> vel_VelMag_CartH(1);
//	real_ resolution = 2 * HSML;
//	int3 cartesianGridDims;
//	int tStepCartesianTotal = 1000000;
//	int tStepCartesianSlice = 100000;
//	int tStepPoiseuilleProf = 1000; //tStepCartesianSlice;
//
//	int stepCalcCartesian = min(tStepCartesianTotal, tStepCartesianSlice);
//	stepCalcCartesian = min(stepCalcCartesian, tStepPoiseuilleProf);
//
//	if (tStep % stepCalcCartesian == 0) {
//		MapSPH_ToGrid(resolution, cartesianGridDims, rho_Pres_CartH, vel_VelMag_CartH, posRadD, velMasD, rhoPresMuD,
//				referenceArray[referenceArray.size() - 1].y, paramsH);
//	}
//	if (tStep % tStepCartesianTotal == 0) {
//		if (tStep / tStepCartesianTotal == 0) {
//			fileNameCartesianTotal.open("dataCartesianTotal.txt");
//			fileNameCartesianTotal<<"variables = \"x\", \"y\", \"z\", \"Vx\", \"Vy\", \"Vz\", \"Velocity Magnitude\", \"Rho\", \"Pressure\"\n";
//		} else {
//			fileNameCartesianTotal .open("dataCartesianTotal.txt", ios::app);
//		}
//		fileNameCartesianTotal<<"zone I = "<<cartesianGridDims.x<<", J = "<<cartesianGridDims.y<<", K = "<<cartesianGridDims.z<<endl;
//		stringstream ssCartesianTotal;
//		for (int k = 0; k < cartesianGridDims.z; k++) {
//			for (int j = 0; j < cartesianGridDims.y; j++) {
//				for (int i = 0; i < cartesianGridDims.x; i++) {
//					int index = i + j * cartesianGridDims.x + k * cartesianGridDims.x * cartesianGridDims.y;
//					real3 gridNodeLoc = resolution * R3(i, j, k) + paramsH.worldOrigin;
//					ssCartesianTotal<<gridNodeLoc.x<<", "<< gridNodeLoc.y<<", "<< gridNodeLoc.z<<", "<<
//							vel_VelMag_CartH[index].x<<", "<< vel_VelMag_CartH[index].y<<", "<< vel_VelMag_CartH[index].z<<", "<< vel_VelMag_CartH[index].w<<", "<<
//							rho_Pres_CartH[index].x<<", "<< rho_Pres_CartH[index].y<<endl;
//				}
//			}
//		}
//		fileNameCartesianTotal<<ssCartesianTotal.str();
//		fileNameCartesianTotal.close();
//	}
//////////-+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //comcom
//	ofstream fileNameCartesianMidplane;
//	if (tStep % tStepCartesianSlice == 0) {
//		if (tStep / tStepCartesianSlice == 0) {
//			fileNameCartesianMidplane.open("dataCartesianMidplane.txt");
//			fileNameCartesianMidplane<<"variables = \"x\", \"z\", \"Vx\", \"Vy\", \"Vz\", \"Velocity Magnitude\", \"Rho\", \"Pressure\"\n";
//		} else {
//			fileNameCartesianMidplane .open("dataCartesianMidplane.txt", ios::app);
//		}
//		fileNameCartesianMidplane<< "zone I = "<<cartesianGridDims.x<<", J = "<<cartesianGridDims.z<<"\n";
//		int j = cartesianGridDims.y / 2;
//		stringstream ssCartesianMidplane;
//		for (int k = 0; k < cartesianGridDims.z; k++) {
//			for (int i = 0; i < cartesianGridDims.x; i++) {
//				int index = i + j * cartesianGridDims.x + k * cartesianGridDims.x * cartesianGridDims.y;
//				real3 gridNodeLoc = resolution * R3(i, j, k) + paramsH.worldOrigin;
//				ssCartesianMidplane<<gridNodeLoc.x<<", "<< gridNodeLoc.z<<", "<< vel_VelMag_CartH[index].x<<", "<<
//						vel_VelMag_CartH[index].y<<", "<< vel_VelMag_CartH[index].z<<", "<< vel_VelMag_CartH[index].w<<", "<< rho_Pres_CartH[index].x<<", "<<
//						rho_Pres_CartH[index].y<<endl;
//			}
//		}
//		fileNameCartesianMidplane<<ssCartesianMidplane.str();
//		fileNameCartesianMidplane.close();
//	}
//	rho_Pres_CartH.clear();
//////////-+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++comcom
//	ofstream fileVelocityProfPoiseuille;
//	if (tStep % tStepPoiseuilleProf == 0) {
//		if (tStep / tStepPoiseuilleProf == 0) {
//			fileVelocityProfPoiseuille.open("dataVelProfile.txt");
//			fileVelocityProfPoiseuille<< "variables = \"Z(m)\", \"Vx(m/s)\"\n";
//
//		} else {
//			fileVelocityProfPoiseuille.open("dataVelProfile.txt", ios::app);
//		}
//		fileVelocityProfPoiseuille<<"zone T=\"t = "<<delT * tStep<<"\""endl;
//		stringstream ssVelocityProfPoiseuille;
//		int j = cartesianGridDims.y / 2;
//		int i = cartesianGridDims.x / 2;
//		for (int k = 0; k < cartesianGridDims.z; k++) {
//			int index = i + j * cartesianGridDims.x + k * cartesianGridDims.x * cartesianGridDims.y;
//			real3 gridNodeLoc = resolution * R3(i, j, k) + paramsH.worldOrigin;
//			if (gridNodeLoc.z > 1 * sizeScale && gridNodeLoc.z < 2 * sizeScale) {
//				ssVelocityProfPoiseuille<<gridNodeLoc.z<<", "<< vel_VelMag_CartH[index].x<<endl;
//			}
//		}
//		fileVelocityProfPoiseuille<<ssVelocityProfPoiseuille.str();
//		fileVelocityProfPoiseuille.close();
//	}
//	vel_VelMag_CartH.clear();
//////-+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
	ofstream fileRigidParticleCenterVsTimeAndDistance;
	int numRigidBodiesInOnePeriod = int(posRigidH.size() / real_(nPeriod) + .5);
	int tStepRigidCenterPos = 1000;
	if (tStep % tStepRigidCenterPos == 0) {
		if (tStep / tStepRigidCenterPos == 0) {
			fileRigidParticleCenterVsTimeAndDistance.open("dataRigidCenterVsTimeAndDistance.txt");
			fileRigidParticleCenterVsTimeAndDistance<<"(t, x, dist[or y], dum[or z],   x_cumul, y, z,   vx, vy, vz,   omega_x, omega_y, omega_z) (sequentially for all particles), average flow velocity (x, y, z, magnitude), channel radius\n" << endl;
		} else {
			fileRigidParticleCenterVsTimeAndDistance.open("dataRigidCenterVsTimeAndDistance.txt", ios::app);
		}
//		(void) thrust::reduce_by_key(rigidIdentifierD.begin(), rigidIdentifierD.end(), torqueParticlesD.begin(), dummyIdentify.begin(),
//					totalTorque3.begin(), binary_pred, thrust::plus<real3>());

		printf("channel radius %f\n", channelRadius);
		real4 sumVelocity = R4(0);
		real4 initSumR4 = R4(0);
		sumVelocity = thrust::reduce(velMasD.begin() + referenceArray[0].x, velMasD.begin() + referenceArray[0].y, initSumR4, thrust::plus<real4>());
		real3 aveVel = R3(sumVelocity / (referenceArray[0].y - referenceArray[0].x));

		stringstream ssParticleCenterVsTime;
		if (referenceArray.size() > 2) {
			for (int j = 0; j < numRigidBodiesInOnePeriod; j++) {
				real3 p_rigid = posRigidH[j];
				real3 v_rigid = R3(velMassRigidH[j]);
				real3 omega_rigid = omegaLRF_H[j];
				//printf("position %f %f %f %f\n", p_rigid.x, p_rigid.y, p_rigid.z,0);
				real3 p_rigidCumul = posRigidCumulativeH[j];
//				//***cartesian distance (channel, duct)
//				ssParticleCenterVsTime << tStep * delT << ", " << p_rigid.y << ", " << p_rigid.z;
//				ssParticleCenterVsDistance << p_rigidCumul.x << ", " << p_rigid.y << ", " << p_rigid.z;

//				//***radial distance (tube)
				real2 dist2 = R2(channelCenterYZ.x - p_rigid.y, channelCenterYZ.y - p_rigid.z);
				printf("center %f %f and radius %f and py and pz %f %f\n", channelCenterYZ.x, channelCenterYZ.y, channelRadius, p_rigid.y, p_rigid.z);
				ssParticleCenterVsTime << tStep * delT << ", " <<  p_rigidCumul.x << ", " <<
						length(dist2) / channelRadius << ", " << length(dist2) / channelRadius << ", " <<
						p_rigidCumul.x << ", " << p_rigid.y << ", " << p_rigid.z << ", " <<
						v_rigid.x << ", " << v_rigid.y << ", " << v_rigid.z << ", " <<
						omega_rigid.x << ", " << omega_rigid.y << ", " << omega_rigid.z << ", " << aveVel.x << ", " << aveVel.y << ", " << aveVel.z << ", " << length(aveVel) << ", " << channelRadius << ", ";
			}
			ssParticleCenterVsTime<<endl;
			//fprintf(fileRigidParticleCenterVsTimeAndDistance, "\n");
			//fprintf(fileRigidParticleCenterVsDistance, "\n");
		}
		fileRigidParticleCenterVsTimeAndDistance << ssParticleCenterVsTime.str();
		fileRigidParticleCenterVsTimeAndDistance.close();
	}
//////-+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
		ofstream fileRigidParticlesDataForTecplot;
		int tStepRigidParticlesDataForTecplot = 1000;
		if (tStep % tStepRigidParticlesDataForTecplot == 0) {
			if (tStep / tStepRigidParticlesDataForTecplot == 0) {
				fileRigidParticlesDataForTecplot.open("dataRigidParticlesDataForTecplot.txt");
				fileRigidParticlesDataForTecplot<<"PipeRadius, PipeLength\n";
				fileRigidParticlesDataForTecplot<<	channelRadius <<", "<< cMax.x - cMin.x<<", "<< posRigidH.size()<<endl;
				fileRigidParticlesDataForTecplot<<"variables = \"t(s)\", \"x\", \"y\", \"z\", \"r\", \"CumulX\", \"vX\", \"vY\", \"vZ\", \"velMagnitude\", \"angleAxisXWithPipeAxis\", \"angleAxisYWithPipeAxis\", \"angleAxisZWithPipeAxis\"\n";
			} else {
				fileRigidParticlesDataForTecplot.open("dataRigidParticlesDataForTecplot.txt", ios::app);
			}
			fileRigidParticlesDataForTecplot<<"zone\n";
			stringstream ssRigidParticlesDataForTecplot;
			for (int j = 0; j < posRigidH.size(); j++) {
				real3 p_rigid = posRigidH[j];

				//rotate the principal axis
				real3 aD1 = AD1[j];
				real3 aD2 = AD2[j];
				real3 aD3 = AD3[j];
				real3 axisX = R3(aD1.x, aD2.x, aD3.x);
				real3 axisY = R3(aD1.y, aD2.y, aD3.y);
				real3 axisZ = R3(aD1.z, aD2.z, aD3.z);

				real4 q_rigid = qH1[j];
				real3 p_rigidCumul = posRigidCumulativeH[j];
				real3 v_rigid = R3(velMassRigidH[j]);
				real2 dist2 = R2(channelCenterYZ.x - p_rigid.y, channelCenterYZ.y - p_rigid.z);
				real_ angleAxisXWithPipeAxis = AngleF3F3(axisX, R3(1, 0, 0));
				real_ angleAxisYWithPipeAxis = AngleF3F3(axisY, R3(1, 0, 0));
				real_ angleAxisZWithPipeAxis = AngleF3F3(axisZ, R3(1, 0, 0));

				ssRigidParticlesDataForTecplot<<tStep * delT<<", "<<p_rigid.x<<", "<<p_rigid.y<<", "<<p_rigid.z<<", "<<length(dist2) / channelRadius<<", "<<p_rigidCumul.x<<", "<<v_rigid.x<<", "<<v_rigid.y<<", "<<v_rigid.z<<", "<<length(v_rigid)<<", "<<angleAxisXWithPipeAxis<<", "<<angleAxisYWithPipeAxis<<", "<<angleAxisZWithPipeAxis<<endl;
			}
			fileRigidParticlesDataForTecplot << ssRigidParticlesDataForTecplot.str();
			fileRigidParticlesDataForTecplot.close();
		}
//////-+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++com
		ofstream fileNameRigidBodies;
		ofstream fileNameFluidParticles;
		ofstream fileNameBoundaries;
		ofstream fileNameFluidBoundaries;

		system("mkdir -p povFiles");
		int tStepsPovFiles = 2000;
		if (tStep % tStepsPovFiles == 0) {
			if (tStep / tStepsPovFiles == 0) {
						//linux. In windows, it is System instead of system (to invoke a command in the command line)
				system("rm povFiles/*.csv");
			}
			char fileCounter[5];
			int dumNumChar = sprintf(fileCounter, "%d", int(tStep / tStepsPovFiles) );

			char nameRigid[255];
			sprintf(nameRigid, "povFiles/rigid");
			strcat(nameRigid, fileCounter);
			strcat(nameRigid, ".csv");
			char nameFluid[255];
			sprintf(nameFluid, "povFiles/fluid");
			strcat(nameFluid, fileCounter);
			strcat(nameFluid, ".csv");
			char nameBoundary[255];
			sprintf(nameBoundary, "povFiles/boundary");
			strcat(nameBoundary, fileCounter);
			strcat(nameBoundary, ".csv");
			char nameFluidBoundaries[255];
			sprintf(nameFluidBoundaries, "povFiles/fluid_boundary");
			strcat(nameFluidBoundaries, fileCounter);
			strcat(nameFluidBoundaries, ".csv");

			fileNameRigidBodies.open(nameRigid);
			stringstream ssRigidBodies;
			if (referenceArray.size() > 2) {
				const int numRigidBodies = posRigidH.size();
				for (int j = 0; j < numRigidBodies; j++) {
					real3 p_rigid = posRigidH[j];
					real4 q_rigid = qH1[j];
					real4 velMassRigid = velMassRigidH[j];
					ssRigidBodies<<tStep * delT<<", "<< p_rigid.x<<", "<< p_rigid.y<<", "<< p_rigid.z<<", "<< velMassRigid.x << ", " <<  velMassRigid.y << ", " <<  velMassRigid.z <<", "<< length(R3(velMassRigid)) <<  ", "<< length(R3(velMassRigid)) << ", "<< q_rigid.x<<", "<< q_rigid.y<<", "<< q_rigid.z<<", "<< q_rigid.w<<", "<<endl;
				}
			}
			fileNameRigidBodies << ssRigidBodies.str();
			fileNameRigidBodies.close();

			fileNameFluidParticles.open(nameFluid);
			stringstream ssFluidParticles;
			for (int i = referenceArray[0].x; i < referenceArray[0].y; i++) {
				real3 pos = posRadH[i];
				real3 vel = R3(velMasH[i]);
				real4 rP = rhoPresMuH[i];
				real_ velMag = length(vel);
				ssFluidParticles<< pos.x<<", "<< pos.y<<", "<< pos.z<<", "<< vel.x<<", "<< vel.y<<", "<< vel.z<<", "<< velMag<<", "<< rP.x<<", "<< rP.y<<", "<< rP.w<<", "<<endl;
			}
			fileNameFluidParticles<<ssFluidParticles.str();
			fileNameFluidParticles.close();

			fileNameBoundaries.open(nameBoundary);
			stringstream ssBoundary;
			for (int i = referenceArray[1].x; i < referenceArray[1].y; i++) {
				real3 pos = posRadH[i];
				real3 vel = R3(velMasH[i]);
				real4 rP = rhoPresMuH[i];
				real_ velMag = length(vel);
				ssBoundary<<pos.x<<", "<< pos.y<<", "<< pos.z<<", "<< vel.x<<", "<< vel.y<<", "<< vel.z<<", "<< velMag<<", "<< rP.x<<", "<< rP.y<<", "<< rP.w<<", "<<endl;
			}
			fileNameBoundaries << ssBoundary.str();
			fileNameBoundaries.close();

			fileNameFluidBoundaries.open(nameFluidBoundaries);
			stringstream ssFluidBoundaryParticles;
	//		ssFluidBoundaryParticles.precision(20);
			for (int i = referenceArray[0].x; i < referenceArray[1].y; i++) {
				real3 pos = posRadH[i];
				real3 vel = R3(velMasH[i]);
				real4 rP = rhoPresMuH[i];
				real_ velMag = length(vel);
				ssFluidBoundaryParticles<< pos.x<<", "<< pos.y<<", "<< pos.z<<", "<< vel.x<<", "<< vel.y<<", "<< vel.z<<", "<< velMag<<", "<< rP.x<<", "<< rP.y<<", "<< rP.z<<", "<< rP.w<<endl;
			}
			fileNameFluidBoundaries<<ssFluidBoundaryParticles.str();
			fileNameFluidBoundaries.close();
		}
	posRadH.clear();
	velMasH.clear();
	rhoPresMuH.clear();
	rigidIdentifierH.clear();
	posRigidH.clear();
	posRigidCumulativeH.clear();
	velMassRigidH.clear();
	qH1.clear();
	omegaLRF_H.clear();
}

//*******************************************************************************************************************************
void PrintToFileDistribution(
		thrust::device_vector<int> & distributionD,
		real_ channelRadius,
		int numberOfSections,
		int tStep) {
	real_ dR = channelRadius / numberOfSections;
	int stepSaveDistribution = 1000;
	FILE *fileNameRadialDistribution;
	FILE *fileNameRadialDistribution_Normalized;
	if (tStep % stepSaveDistribution == 0) {
		if (tStep / stepSaveDistribution == 0) {
			fileNameRadialDistribution = fopen("radialDistribution.txt", "w");
			fprintf(fileNameRadialDistribution,"variables = \"r\", \"N\"\n");
			fileNameRadialDistribution_Normalized = fopen("radialDistributionNormalized.txt", "w");
			fprintf(fileNameRadialDistribution_Normalized,"variables = \"r\", \"N/r\"\n");
		} else {
			fileNameRadialDistribution = fopen("radialDistribution.txt", "a");
			fileNameRadialDistribution_Normalized = fopen("radialDistributionNormalized.txt", "a");
		}
		fprintf(fileNameRadialDistribution, "zone\n");
		fprintf(fileNameRadialDistribution_Normalized, "zone\n");
		for (int i = 0; i < distributionD.size(); i++) {
			real_ radialPos = dR * (i + 1);
			int distribution = distributionD[i];
			fprintf(fileNameRadialDistribution, "%f, %d\n", radialPos, distribution);
			fprintf(fileNameRadialDistribution_Normalized, "%f, %f\n", radialPos, distribution / radialPos);
		}
		fflush(fileNameRadialDistribution);
		fclose(fileNameRadialDistribution);
		fflush(fileNameRadialDistribution_Normalized);
		fclose(fileNameRadialDistribution_Normalized);
	}
}
