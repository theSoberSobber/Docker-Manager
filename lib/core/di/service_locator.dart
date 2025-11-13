import 'package:get_it/get_it.dart';
import '../../domain/repositories/docker_repository.dart';
import '../../domain/repositories/server_repository.dart';
import '../../domain/services/docker_operations_service.dart';
import '../../domain/services/container_creation_service.dart';
import '../../domain/services/image_management_service.dart';
import '../../data/repositories/docker_repository_impl.dart';
import '../../data/repositories/server_repository_impl.dart';
import '../../data/services/docker_operations_service_impl.dart';
import '../../data/services/container_creation_service_impl.dart';
import '../../data/services/image_management_service_impl.dart';
import '../../data/services/docker_registry_service.dart';
import '../../data/services/ssh_connection_service.dart';

final getIt = GetIt.instance;

/// Setup dependency injection for the entire app
/// Call this once at app startup before runApp()
void setupServiceLocator() {
  // Core Infrastructure - Singleton
  getIt.registerSingleton<SSHConnectionService>(SSHConnectionService());
  
  getIt.registerSingleton<DockerRegistryService>(DockerRegistryService());

  // Repositories - Singleton (reuse across app)
  getIt.registerSingleton<DockerRepository>(
    DockerRepositoryImpl(),
  );
  
  getIt.registerSingleton<ServerRepository>(
    ServerRepositoryImpl(),
  );

  // Domain Services - Singleton
  getIt.registerSingleton<DockerOperationsService>(
    DockerOperationsServiceImpl(
      dockerRepository: getIt<DockerRepository>(),
      sshService: getIt<SSHConnectionService>(),
    ),
  );
  
  getIt.registerSingleton<ContainerCreationService>(
    ContainerCreationServiceImpl(
      sshService: getIt<SSHConnectionService>(),
    ),
  );
  
  getIt.registerSingleton<ImageManagementService>(
    ImageManagementServiceImpl(
      sshService: getIt<SSHConnectionService>(),
    ),
  );
}
