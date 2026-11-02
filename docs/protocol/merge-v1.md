# EchoSubs 合并协议 v1

## 身份与状态

两条传输统一调用 `SyncEngine.ingest(StoredObject)`。顺序为账本边界检查、`EnvelopeCodec.open` 认证/协议版本检查、对象账本/批次/摘要自洽校验，最后才写事务。未知版本、认证失败、跨账本或伪摘要抛出安全 EchoFailure，不登记接收、不隔离合法已有对象。密码实现不变。

ID 沿用领域层128位安全随机小写hex。ChangeBatch是原子业务单位，Mutation为完整实体或null墓碑，parentBatchIds只能引用写过该实体的批次。时间戳不用于判定赢家。

projection.entities仅含确认实体；projection.pendingBatchIds只表示缺依赖及其后继。snapshot.pendingUploadIds为网络outbox，旧外层pendingBatchIds是兼容别名。离线未上传不妨碍本地确认或完整备份。receivedBatchIds是认证对象的持久接收收据（包括pending），不是业务已确认列表。

IngestResult为applied/duplicate/pending/conflict/quarantined。duplicate只表示完全相同密文已持久保存，不代表业务确认，调用方仍需读snapshot。后到父可释放pending，后到并发可撤回之前暂时确认。watch与snapshot使用同一纯分析器。

## DAG与原子冲突

`materialize(Set<ChangeBatch>)`返回投影；`analyzeBatches`另外返回合法且依赖完整的heads、隔离IDs与unsafeRefs。错实体父引用、环、非法解决及污染后继从正常heads排除；隔离不冒充永久pending。

按DAG顺序验证每个候选的因果past：每个修改必须引用该past内同实体的全部heads。多个互不为祖先的heads出现时，撤回分叉后不属于共同历史的全部版本批次，再沿批次依赖闭包撤回所有后继。该批所有其他写入也撤回，不能只隐藏订阅而留下付款。

重复检查撤回后的图至稳定。若解决记录被撤回，其曾解决的整个争议组件也继续撤回，防止旧付款漏回。共享写入实体或依赖边连接的撤回批次构成组件。Conflict.competingBatchIds包含整个组件，不只tips；affectedRefs覆盖所有写入实体，ID取组件最小批次ID。过期检测应比较完整Conflict，不能只比ID。

从剩余批次重建共同确认视图，最终墓碑不在entities中；独立实体仍合并。费用只消费确认投影的付款，保持整数最小货币单位。

## 完整解决与未来并发

`LedgerRepository.resolve(Conflict,List<Mutation>)`保留每次root keyProof验证。事务内检查冲突未变化、覆盖组件全部refs、每项引用全部合法heads，写入业务、唯一密文、outbox、冲突索引。每个refs必须明确给完整保留值或null，不能省略争议付款。普通commit/renew/AppServices.heads拒绝冲突或隔离实体，不能静默用表单解决。

接收端同样验证完整组件，且相对于候选的**因果past**。未来未知并发后继使旧解决参与新冲突，不会让旧解决因到达顺序不同而变成非法。

虚构轨迹：

1. O创建订阅S。A引用O更新S并创建PA；B引用O更新S并创建PB。
2. 收齐A/B后：确认S=O，无PA/PB；组件为A/B及S/PA/PB。
3. R只写S[A,B]而省PA/PB：隔离R，不释放两笔付款。
4. 完整R写S[A,B]、PA[A]、PB[B]，保留PA、删除PB：确认S=R，仅PA计入actualPaid。
5. 未见R的设备写C引用A更新S/PA：任意顺序下R仍合法，但与C形成新冲突；A/B也保持待确认，恢复S=O、无争议付款。
6. D引用A的PA并创建分类X，E再更新X：闭包包含D/E/X。解决需覆盖S/PA/PB/X及各自heads；漏掉X非法。

## 隔离、审计与转发

相同ID+原始密文去重；同ID不同认证密文（含错误重加密同正文）视为不可变对象碰撞，禁止首到者胜出。原change_batches/cipher_objects保留；schema3 quarantined_objects保存每份候选ledgerId/batchId/sha256/bytes/body/reason，其中body是该bytes认证得到的规范正文，reason仅idCollision或invalidCausality。沿用codec大小限制、本地明文隐私边界；不存密钥或未认证垃圾。

碰撞ID及其依赖闭包从confirmed/eligible排除，相关outbox移除，历史不删除。隔离、业务撤回及冲突索引同事务提交。snapshot.quarantinedBatchIds、causal.unsafeRefs为后续异常UI的明确状态；本任务不提供强制选中碰撞候选的恢复功能。

`LedgerStore.quarantinedObjects()` / `snapshot.quarantinedObjects`返回不可变QuarantineCandidate，含每份原bytes、摘要、认证body与reason。`objects()`仍只返回每ID的原cipher_objects存档，**不含碰撞第二份**。后续完整备份与LAN/协调器必须额外枚举quarantine candidates，按账本+批次+摘要去重转发已认证原bytes，让第三节点也能看到碰撞。不能只转发首份、不能重新seal、不能传播未认证垃圾；接收候选仍走ingest认证。本任务不实现协调器或备份恢复。

## 验证与范围

虚构数据、真实独立SQLite文件和AEAD测试覆盖三副本重排/重复投递、100固定种子、删除编辑、双续费、子先于父、认证拒绝、不同refs的同ID碰撞、完整/部分解决、未来并发、多实体闭包、事务检查点崩溃重放、schema1/2迁移及回滚、未来数据库版本拒绝。

当前从完整不可变历史重建，单个snapshot缓存因果分析；尚未做大型历史增量索引或性能基准。历史压缩、隔离处理UI、提醒、传输和备份属于后续任务，不删除历史。
